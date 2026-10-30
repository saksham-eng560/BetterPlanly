# Project skills

Claude Code loads these skills automatically in any session that opens this repository. Invoke a skill with `/<name>`.

| Skill | Source | License |
|---|---|---|
| `karpathy-guidelines` | [forrestchang/andrej-karpathy-skills](https://github.com/forrestchang/andrej-karpathy-skills) | MIT |
| `improve-codebase-architecture` | [mattpocock/skills](https://github.com/mattpocock/skills) | MIT (see `LICENSE`) |
| `codebase-design`, `grilling`, `domain-modeling` | [mattpocock/skills](https://github.com/mattpocock/skills). Used by `improve-codebase-architecture` | MIT (see `LICENSE`) |
| `emil-design-eng` | [emilkowalski/skill](https://github.com/emilkowalski/skill) | MIT (see `LICENSE`) |
| `apple-design` | Written for this project from Apple's Human Interface Guidelines | Project license |

`improve-codebase-architecture` sets `disable-model-invocation: true`, so Claude can't start it on its own. Run it yourself with `/improve-codebase-architecture`.

graphify is not vendored here. Install it with `pip install graphifyy && graphify install`.
