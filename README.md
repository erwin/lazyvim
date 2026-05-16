# 💤 LazyVim

Based on the amazing [LazyVim](https://github.com/LazyVim/LazyVim).
See LazyVim's [documentation](https://lazyvim.github.io/installation) to get started.

# Local customizations

`./lua/plugins/wakatime.lua` (gf)


gqG        ~ from current position, re-wrap all following lines of file
z=         ~ Open neovim spelling suggestions
zg         ~ Spell Good (Add to Dictionary)
zug        ~ Undo `zg` (remove from Dictionary)

]s         ~ Jump to next spelling error
:spellr    ~ Repeat fix of same spelling error

leader-fg  ~ git differences (shell CTRL+G = git diff)
leader+/   ~ grep in current project
leader+tab ~ tab stuff

CTRL+]     ~ jump to definition
Ctrl+O     ~ return from definition
Ctrl+i     ~ reverse of CTRL+O

CTRL+6     ~ jump back to previous buffer

{          ~ jump to start of paragraph
}          ~ jump to end of paragraph

(          ~ jump to start of sentence
)          ~ jump to end of sentence

w          ~ jump to start of next word
b          ~ jump to start of prev word

e          ~ jump to end of next word
ge         ~ jump to the end of prev word
(:h word-motions)
