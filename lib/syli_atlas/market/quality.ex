defmodule SyliAtlas.Market.Quality do
  @moduledoc """
  Checks run on every record before it becomes an observation. A check
  gives a verdict and, possibly, an issue:

    * `:ok` – stored and publishable;
    * `:flag` – stored and published with a warning shown next to it;
    * `:hold` – stored but not published until someone decides;
    * `:reject` – not stored (an impossible value).

  Issues stay open while the problem lasts and close themselves when a
  later import no longer shows it. Thresholds are per subject kind: an
  index moving 5 % in a day, a share 30 %.
  """
  import Ecto.Query
  alias SyliAtlas.Repo
  alias SyliAtlas.Market.QualityIssue

  @index_jump 5.0
  @share_jump 30.0
  @stale_business_days 2

  @index_rules ~w(index_missing stale suspect_change)
  # Rules about one session's figure, not a lasting state.
  @event_rules ~w(suspect_change abnormal_change invalid_price)
  @security_rules ~w(invalid_price stale abnormal_change no_trade)

  @doc "Checks an index record: {verdict, [issue]}."
  def check_index(record, today \\ Date.utc_today()) do
    issues =
      [
        is_nil(number(record.value)) &&
          issue("index_missing", "mid", "No index value from the source"),
        stale?(record.as_of, today) &&
          issue("stale", "mid", "No session since #{date(record.as_of)}", %{
            "as_of" => date(record.as_of)
          }),
        suspect_index_change?(record) &&
          issue(
            "suspect_change",
            "high",
            "Daily change #{record.change_pct} % (year to date #{record.ytd_pct} %)",
            %{"change_pct" => record.change_pct, "ytd_pct" => record.ytd_pct}
          )
      ]
      |> Enum.filter(& &1)

    verdict =
      cond do
        is_nil(number(record.value)) -> :reject
        Enum.any?(issues, &(&1.rule == "suspect_change")) -> :flag
        true -> :ok
      end

    {verdict, issues, @index_rules}
  end

  @doc "Checks a security record: {verdict, [issue]}."
  def check_security(record, today \\ Date.utc_today()) do
    close = number(record.close)
    chg = number(record.change_pct)
    traded? = is_integer(record.volume) and record.volume > 0

    issues =
      [
        (is_nil(close) or close <= 0) &&
          issue("invalid_price", "high", "Close missing or not positive"),
        stale?(record.as_of, today) &&
          issue("stale", "mid", "No session since #{date(record.as_of)}", %{
            "as_of" => date(record.as_of)
          }),
        (traded? and is_number(chg) and abs(chg) > @share_jump) &&
          issue("abnormal_change", "high", "Daily change of #{chg} %", %{"change_pct" => chg}),
        (is_nil(chg) and not traded?) &&
          issue("no_trade", "low", "No change and no volume for the session")
      ]
      |> Enum.filter(& &1)

    verdict =
      cond do
        is_nil(close) or close <= 0 -> :reject
        Enum.any?(issues, &(&1.rule == "abnormal_change")) -> :hold
        true -> :ok
      end

    {verdict, issues, @security_rules}
  end

  @doc """
  Brings the open issues of a subject in line with a check: opens the new
  ones, refreshes those still there, resolves the checked rules that no
  longer apply.
  """
  def sync!(subject_type, subject_id, trade_date, issues, checked_rules) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    existing =
      Repo.all(
        from q in QualityIssue,
          where:
            q.subject_type == ^subject_type and q.subject_id == ^subject_id and
              q.status in ["open", "accepted", "ignored"],
          order_by: q.id
      )

    open = for(q <- existing, q.status == "open", into: %{}, do: {q.rule, q})
    # Decided in the admin (accepted or ignored): not reopened while the
    # same problem lasts. An event (a price jump) on another session is a
    # new problem.
    dismissed = for(q <- existing, q.status != "open", into: %{}, do: {q.rule, q})

    found = MapSet.new(issues, & &1.rule)

    for i <- issues do
      case {open[i.rule], dismissed[i.rule]} do
        {nil, %QualityIssue{} = d}
        when i.rule not in @event_rules or d.trade_date == trade_date ->
          :ok

        {nil, _} ->
          Repo.insert!(%QualityIssue{
            rule: i.rule,
            severity: i.severity,
            subject_type: subject_type,
            subject_id: subject_id,
            trade_date: trade_date,
            detail: i.detail,
            data: i.data,
            status: "open",
            detected_at: now
          })

        {existing, _} ->
          existing
          |> Ecto.Changeset.change(detail: i.detail, data: i.data, trade_date: trade_date)
          |> Repo.update!()
      end
    end

    for {rule, existing} <- open, rule in checked_rules, not MapSet.member?(found, rule) do
      existing |> Ecto.Changeset.change(status: "resolved", resolved_at: now) |> Repo.update!()
    end

    # A decided problem that went away no longer holds back a new one.
    for {rule, d} <- dismissed, rule in checked_rules, not MapSet.member?(found, rule) do
      d |> Ecto.Changeset.change(status: "resolved") |> Repo.update!()
    end

    :ok
  end

  def open_issues(subject_type, subject_ids) when is_list(subject_ids) do
    Repo.all(
      from q in QualityIssue,
        where:
          q.subject_type == ^subject_type and q.subject_id in ^subject_ids and q.status == "open",
        order_by: [q.subject_id, q.rule]
    )
  end

  def list_open, do: Repo.all(from q in QualityIssue, where: q.status == "open", order_by: q.id)

  def held?(subject_type, subject_id, trade_date) do
    Repo.exists?(
      from q in QualityIssue,
        where:
          q.subject_type == ^subject_type and q.subject_id == ^subject_id and
            q.rule == "abnormal_change" and q.status == "open" and q.trade_date == ^trade_date
    )
  end

  # An index change equal to its change since 1 January is a mix-up in the
  # source, not a session; so is an index jumping 5 % in a day.
  defp suspect_index_change?(%{change_pct: chg} = record) do
    chg = number(chg)
    ytd = number(Map.get(record, :ytd_pct))

    cond do
      is_nil(chg) -> false
      is_number(ytd) and chg != 0 and abs(abs(chg) - abs(ytd)) < 0.005 -> true
      abs(chg) > @index_jump -> true
      true -> false
    end
  end

  @doc "Business days (Monday to Friday) after `from` up to and including `to`."
  def business_days_between(%Date{} = from, %Date{} = to) do
    if Date.compare(from, to) != :lt do
      0
    else
      from
      |> Date.add(1)
      |> Date.range(to)
      |> Enum.count(&(Date.day_of_week(&1) <= 5))
    end
  end

  defp stale?(nil, _today), do: false

  defp stale?(%DateTime{} = as_of, today),
    do: business_days_between(DateTime.to_date(as_of), today) > @stale_business_days

  defp date(nil), do: nil
  defp date(%DateTime{} = dt), do: dt |> DateTime.to_date() |> Date.to_iso8601()

  defp issue(rule, severity, detail, data \\ %{}),
    do: %{rule: rule, severity: severity, detail: detail, data: data}

  defp number(n) when is_number(n), do: n
  defp number(%Decimal{} = d), do: Decimal.to_float(d)
  defp number(_), do: nil
end
