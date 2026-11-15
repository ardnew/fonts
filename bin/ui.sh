#!/usr/bin/env bash

# Colors match the configured Neovim Kanagawa Dragon palette.
export GUM_CONFIRM_PROMPT_FOREGROUND=${GUM_CONFIRM_PROMPT_FOREGROUND-'#7DAEA3'}
export GUM_CONFIRM_SELECTED_FOREGROUND=${GUM_CONFIRM_SELECTED_FOREGROUND-'#ECEFF4'}
export GUM_CONFIRM_SELECTED_BACKGROUND=${GUM_CONFIRM_SELECTED_BACKGROUND-'#3E4451'}
export GUM_CONFIRM_UNSELECTED_FOREGROUND=${GUM_CONFIRM_UNSELECTED_FOREGROUND-'#ABB2BF'}
export GUM_CHOOSE_HEADER_FOREGROUND=${GUM_CHOOSE_HEADER_FOREGROUND-'#7DAEA3'}
export GUM_CHOOSE_CURSOR_FOREGROUND=${GUM_CHOOSE_CURSOR_FOREGROUND-'#D3869B'}
export GUM_CHOOSE_ITEM_FOREGROUND=${GUM_CHOOSE_ITEM_FOREGROUND-'#D8D8D2'}
export GUM_CHOOSE_SELECTED_FOREGROUND=${GUM_CHOOSE_SELECTED_FOREGROUND-'#ECEFF4'}
export GUM_TABLE_BORDER_FOREGROUND=${GUM_TABLE_BORDER_FOREGROUND-'#ABB2BF'}
export GUM_TABLE_HEADER_FOREGROUND=${GUM_TABLE_HEADER_FOREGROUND-'#7DAEA3'}
export GUM_TABLE_CELL_FOREGROUND=${GUM_TABLE_CELL_FOREGROUND-'#D8D8D2'}
export GUM_SPIN_SPINNER_FOREGROUND=${GUM_SPIN_SPINNER_FOREGROUND-'#D3869B'}
export GUM_SPIN_TITLE_FOREGROUND=${GUM_SPIN_TITLE_FOREGROUND-'#7DAEA3'}

ui_require_gum() {
    if ! command -v gum >/dev/null 2>&1 || ! gum version-check '>= 2.0.2' >/dev/null 2>&1; then
        printf '%s\n' 'Gum 2.0.2 or later is required. Install gum.' >&2
        return 1
    fi
}

ui_render() {
    if [[ -n ${NO_COLOR-} ]]; then
        TERM=dumb gum "$@"
    else
        gum "$@"
    fi
}

ui_info() { ui_render log --level none --message.foreground '#7DAEA3' -- "$1" 2>&1; }
ui_debug() { ui_render log --level none --message.foreground '#ABB2BF' -- "$1" 2>&1; }
ui_success() { ui_render log --level none --message.foreground '#89B482' -- "$1" 2>&1; }
ui_warn() { ui_render log --level warn --level.foreground '#D8A657' -- "$1"; }
ui_error() { ui_render log --level error --level.foreground '#EA6962' -- "$1"; }
ui_heading() { ui_render style --foreground '#7DAEA3' -- "$1"; }
ui_table() { ui_render table --print; }

ui_confirm() {
    if [[ -t 0 ]]; then
        gum confirm --default=false -- "$1"
    else
        local answer
        IFS= read -r answer || return 1
        [[ $answer == y || $answer == Y ]]
    fi
}

ui_choose_prune() {
    gum choose --header "$1" --selected=Remove Remove Skip Quit
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    ui_require_gum || exit 1
    case ${1-} in
    info | debug | success | warn | error | heading | confirm | choose_prune | table)
        operation=$1
        shift
        "ui_$operation" "${1-}"
        ;;
    *)
        ui_error 'Unknown UI operation.'
        exit 2
        ;;
    esac
fi
