defmodule SyliAtlas.CompaniesTest do
  use SyliAtlas.DataCase, async: false

  alias SyliAtlas.Companies
  alias SyliAtlas.Companies.{Company, Verifier}

  @page """
  <html><body><nav>menu</nav>
  <h1>Kamoto Copper Company</h1>
  <p>Kamoto Copper Company -- KCC -- is a copper and cobalt producer in the Democratic Republic of the Congo, jointly owned by Glencore (70%), Gécamines (25%) and the DRC State (5%).</p>
  <p>Located in Kolwezi, in the province of Lualaba, our portfolio of assets includes three open pit mines, one underground mine, the Kamoto concentrator and the Luilu refinery. #{String.duplicate("More text about operations. ", 10)}</p>
  </body></html>
  """

  setup do
    SyliAtlas.Geo.seed_areas!()

    {:ok, c} =
      Companies.create(%{
        "product" => "copper",
        "country" => "COD",
        "name" => "Kamoto Copper Company (KCC)",
        "kind" => "producer",
        "owners" => "Glencore, Gécamines",
        "source_url" => "https://kcc.test/",
        "source_name" => "kcc.test"
      })

    %{company: c}
  end

  defp page(body, type \\ "text/html; charset=utf-8") do
    Req.Test.stub(Verifier.Page, fn conn ->
      conn |> Plug.Conn.put_resp_content_type(type, nil) |> Plug.Conn.send_resp(200, body)
    end)
  end

  defp ai(verdict, excerpt, owners \\ true) do
    Req.Test.stub(Verifier, fn conn ->
      Req.Test.json(conn, %{
        "content" => [
          %{
            "type" => "tool_use",
            "name" => "record_verdict",
            "input" => %{
              "verdict" => verdict,
              "excerpt" => excerpt,
              "owners_confirmed" => owners,
              "reason" => "test"
            }
          }
        ]
      })
    end)
  end

  @quote "Kamoto Copper Company -- KCC -- is a copper and cobalt producer in the Democratic Republic of the Congo"

  test "confirmed word for word: published, with its excerpt", %{company: c} do
    page(@page)
    ai("confirmed", @quote)
    c = Companies.check!(c)
    assert c.status == "published"
    assert c.excerpt == @quote
    assert c.verified_at
    assert [%Company{}] = Companies.published("copper")
  end

  test "an excerpt the page does not contain is refused, and the company hidden", %{company: c} do
    page(@page)

    ai(
      "confirmed",
      "Kamoto Copper Company is the largest copper producer in the Democratic Republic of the Congo"
    )

    c = Companies.check!(c)
    assert c.status == "hidden"
    assert c.note =~ "mot pour mot"
    assert Companies.published("copper") == []
  end

  test "a doubt of the AI hides the company", %{company: c} do
    page(@page)
    ai("not_found", "")
    assert Companies.check!(c).status == "hidden"
  end

  test "a contradiction hides it too", %{company: c} do
    page(@page)
    ai("contradicted", "")
    c = Companies.check!(c)
    assert c.status == "hidden"
    assert c.note =~ "contredit"
  end

  test "owners must be confirmed and named in the page", %{company: c} do
    page(@page)
    ai("confirmed", @quote, false)
    assert Companies.check!(c).status == "hidden"

    {:ok, other} = c |> Company.changeset(%{"owners" => "Glencore, Trafigura"}) |> Repo.update()
    ai("confirmed", @quote, true)
    other = Companies.check!(other)
    assert other.status == "hidden"
    assert other.note =~ "actionnaire"
  end

  test "an excerpt that names neither the company nor the product is refused", %{company: c} do
    page(@page)

    ai(
      "confirmed",
      "Located in Kolwezi, in the province of Lualaba, our portfolio of assets includes three open pit mines"
    )

    assert Companies.check!(c).status == "hidden"
  end

  test "a PDF or an unreachable page is refused", %{company: c} do
    page("%PDF-1.7", "application/pdf")
    ai("confirmed", @quote)
    c = Companies.check!(c)
    assert c.status == "hidden"
    assert c.note =~ "pas une page web"

    Req.Test.stub(Verifier.Page, &Plug.Conn.send_resp(&1, 404, "no"))
    assert Companies.check!(c).note =~ "404"
  end

  test "without an answer from the AI nothing is concluded", %{company: c} do
    page(@page)
    Req.Test.stub(Verifier, &Plug.Conn.send_resp(&1, 529, "overloaded"))
    c = Companies.check!(c)
    assert c.status == "pending"
    assert c.note =~ "vérification impossible"
  end

  test "a company not confirmed for 90 days is hidden", %{company: c} do
    old = DateTime.utc_now() |> DateTime.add(-91, :day) |> DateTime.truncate(:second)

    c
    |> Company.check_changeset(%{status: "published", verified_at: old, checked_at: old})
    |> Repo.update!()

    assert Companies.expire!() == 1
    assert Companies.get!(c.id).status == "hidden"
  end

  test "withdrawn companies are never checked again", %{company: c} do
    c = Companies.withdraw!(c)
    assert Companies.check!(c, fn _ -> raise "not called" end).status == "withdrawn"
    refute Enum.any?(Companies.due(), &(&1.id == c.id))
  end

  test "the seed file adds companies once and checks again those that changed" do
    path = Path.join(System.tmp_dir!(), "companies-#{System.unique_integer([:positive])}.json")

    row = %{
      "product" => "phosphates",
      "country" => "MAR",
      "name" => "OCP",
      "kind" => "state_company",
      "source_url" => "https://ocp.test/",
      "source_name" => "OCP"
    }

    File.write!(path, Jason.encode!([row]))
    assert Companies.sync_seed!(path) == %{added: 1, changed: 0}
    assert Companies.sync_seed!(path) == %{added: 0, changed: 0}

    [ocp] = Enum.filter(Companies.list_all(), &(&1.name == "OCP"))

    Companies.check!(ocp, fn _ ->
      {:confirmed, "OCP mines phosphate in Morocco and exports it."}
    end)

    File.write!(path, Jason.encode!([Map.put(row, "source_url", "https://ocp.test/new")]))
    assert Companies.sync_seed!(path) == %{added: 0, changed: 1}
    assert Companies.get!(ocp.id).status == "pending"
  end

  test "the shipped seed file is valid" do
    for row <- Companies.seed_path() |> File.read!() |> Jason.decode!() do
      assert Company.changeset(%Company{}, row).valid?, inspect(row)
    end
  end
end
