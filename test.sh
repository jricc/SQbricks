CODEX=$(find ~/.vscode/extensions -type f \
  -path '*openai.chatgpt*/bin/*/codex' -executable |
  sort -V | tail -n 1)

"$CODEX" --version
"$CODEX" login status
"$CODEX" doctor