# command alias
alias -g @lf='| less +F'
alias -g @repo='echo "~/Repository"'

# git
export PATH=/usr/local/bin/git:$PATH
alias gb='echo $(git rev-parse --abbrev-ref HEAD)'
alias gb_like='git branch @g $1'
alias gc='git checkout $1'
alias gpush='git push -u origin $1'
alias gpull='(){git pull origin --rebase $1}'
alias gl='git log --oneline'
alias gtree='git log --graph -30 --format="%x09%an%x09%h %d"'
alias gs='git status -s | cut -c4-'
alias gds='git diff --name-only origin/master'
alias gdc="git diff --stat -w -B -I '^\s*\/' origin/master"
alias gcomi='(){~/Script/cmd/commit $1}'

# todo.sh
alias todo='todo.sh'

# iterm
test -e "${HOME}/.iterm2_shell_integration.zsh" && source "${HOME}/.iterm2_shell_integration.zsh"

# starship
eval "$(starship init zsh)"

# git-completionの読み込み
fpath=(~/.zsh $fpath)
zstyle ':completion:*:*:git:*' script ~/.zsh/git-completion.bash
autoload -Uz compinit && compinit

# rbenv
eval "$(rbenv init - zsh)"

# ============
