using Documenter, BaseModelica

cp("./docs/Manifest.toml", "./docs/src/assets/Manifest.toml", force = true)
cp("./docs/Project.toml", "./docs/src/assets/Project.toml", force = true)

pages = [
    "Home" => "index.md",
    "api.md"
]

ENV["GKSwstype"] = "100"

makedocs(modules = [BaseModelica],
    sitename = "BaseModelica.jl",
    clean = true,
    doctest = false,
    linkcheck = true,
    format = Documenter.HTML(assets = ["assets/favicon.ico"],
        canonical = "https://docs.sciml.ai/BaseModelica/stable/"),
    pages = pages)

deploydocs(repo = "github.com/SciML/BaseModelica.jl"; push_preview = true)
