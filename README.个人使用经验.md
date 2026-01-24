原理walkthrough:https://ampcode.com/threads/T-019beeac-b42f-711f-a4e5-5485d29b3647
1. Load the prd skill and create a PRD for [your feature description]
2. Load the ralph skill and convert tasks/prd-[feature-name].md to prd.json
3. ```bash
   mkdir -p scripts/ralph
   cp /path/to/ralph/ralph.sh scripts/ralph/
   # Copy the prompt template for your AI tool of choice:
   cp /path/to/ralph/prompt.md scripts/ralph/prompt.md    # For Amp
   cp /path/to/ralph/AGENTS.md scripts/ralph/AGENTS.md    # For Copilot
   cp /path/to/ralph/CLAUDE.md scripts/ralph/CLAUDE.md    # For Claude Code
   chmod +x scripts/ralph/ralph.sh
   ```
4. 根据项目情况,可以自行调整`prompt.md`, 如你的项目是制作presentation,则可以微调一下(默认是:You are an autonomous coding agent working on a software project.).
5. user level 按需调整.
6. @tasks/prd.json 帮我把这个信息做成walkthrough交互图,我需要看看整体情况.(use walkthrough skill),效果:https://ampcode.com/threads/T-019bf105-2dac-720f-a2b6-f62e76f73baf
7. GitHub Copilot charge by premium request means you only pay 1 request per iteration. awsome. and you can run [copilot-usage-monitor.sh](copilot-usage-monitor.sh) to see details.
8. [ralph.sh](ralph.sh) log detail to files so you can archive the processes of the ralph loops.

> 1. Amp Opus For PRD.md and prd.json
> 2. GitHub Copilot for ralph loops
> 3. monitor for Github Copilot premium request usage
> 4. Walkthrough for Ralph Progress.
> ![img.png](amp-for-prd-and-prd.json-.png)


```bash
➜  usecase git:(main) ✗ tree .
.
├── scripts
│   └── ralph
│       ├── prompt.md
│       └── ralph.sh
└── tasks
    ├── prd-usecase.md
    └── prd.json

```