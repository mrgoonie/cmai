# `prepare-commit-msg-cc-ai` - AI Conventional Commits Message Generator

Tired of manual commit messages?

[![Git Commit](https://imgs.xkcd.com/comics/git_commit.png)](https://xkcd.com/1296/)

Welcome git hook that automatically generates conventional commit messages using AI, based on your staged git changes.

Your commit messages will look like this:

<!-- TODO: @alexanderilyin: Add example commit message screenshot -->

## Attribution

- [`mrgoonie/cmai.git`](https://github.com/mrgoonie/cmai) for the original shell script.
- [OpenRouter](https://openrouter.ai/) for providing the AI API.
- [Conventional Commits](https://www.conventionalcommits.org/) for the commit message format.

## Features

- 🤖 AI-powered commit message generation (using `google/gemini-flash-1.5-8b` - SUPER CHEAP!)
  - Around $0.00001/commit -> $1 per 100K commit messages!
- 📝 Follows [Conventional Commits](https://www.conventionalcommits.org/) format
- 🔒 Secure local API key storage
- 🚀 Automatic git commit and push
- 🐛 Debug mode for troubleshooting
- 💻 Cross-platform support (Windows, Linux, macOS)

## Prerequisites

- `git` installed and configured
- `pre-commit` installed and configured
- `jq` installed
  - Used for escaping JSON
- An [OpenRouter](https://openrouter.ai/) API key
- `curl` installed

## Installation

Export API key for https://openrouter.ai/

```bash
 export OPENROUTER_API_KEY=...
```

1. Install [`pre-commit`](https://pre-commit.com/#install).
2. Add hook configuration to `.pre-commit-config.yaml`.
   ```yaml
   # See https://pre-commit.com for more information
   # See https://pre-commit.com/hooks.html for more hooks
   repos:
     - repo: https://github.com/partcad/cmai
       rev: main
       hooks:
         - id: prepare-commit-msg-cc-ai
   ```

By default only filenames collected using `git diff --cached --name-status` will be sent to OpenRouter. If you want to
share commit diff using `git diff --cached` with OpenRouter and get more detailed commit message then you can use
`--open-source` option. There is also `--debug` option for troubleshooting.

> If you set custom `args` you will have to provide `--commit-msg-filename` as last argument.

```yaml
- id: prepare-commit-msg-cc-ai
  args: [
     "--debug",
     "--open-source",
     "--commit-msg-filename",
]
```

## Security

- API key is stored in environment variable
- No data is stored or logged except the API key
- All communication is done via HTTPS

## Uninstallation

- [`pre-commit uninstall`](https://pre-commit.com/#pre-commit-uninstall)

## Development

Consider reading at least following docs for `pre-commit`:

- [Creating new hooks](https://pre-commit.com/#new-hooks)
- [Supported git hooks - `prepare-commit-msg`](https://pre-commit.com/#prepare-commit-msg)
- [Creating new hooks - `stages`](https://pre-commit.com/#hooks-stages)

You can use following snippet for local testing:

```bash
# Stage some changes
git add .

# Trigger hook
pre-commit try-repo \
   --verbose \
   --hook-stage=prepare-commit-msg \
   --commit-msg-filename=$(mktemp) \
   . \
   prepare-commit-msg-cc-ai \
   --verbose \
   --all-files \
```

## License

MIT License - see LICENSE file for details

## Roadmap

- [ ] Allow override user prompt.
- [ ] Allow override system prompt.
- [ ] Allow direct usage of LLMs.
- [x] Add GitHub stars chart.

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=partcad/prepare-commit-msg-cc-ai&type=Date)](https://star-history.com/#partcad/prepare-commit-msg-cc-ai&Date)
