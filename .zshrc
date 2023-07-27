# command alias
alias -g @g='| grep'
alias -g @lf='| less +F'
alias repo='~/Repository'

# git
alias gb='git rev-parse --abbrev-ref HEAD'
alias gpush='git push origin $1'
alias gpull='(){git pull origin --rebase $1}'
alias gl='git log --oneline'
alias gs='git status -s | cut -c4-'

# iterm
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# starship
eval "$(starship init zsh)"
