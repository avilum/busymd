#!/usr/bin/env bash
set -euo pipefail

# BUSYMD - Markdown Viewer for Busybox and Beyond
# Pure bash markdown renderer with no external dependencies
#
# Usage:
#   ./busymd.sh FILE.md                        # Run as script
#   source busymd.sh && busymd FILE.md         # Use as bash function
#   busymd() { bash /path/to/busymd.sh "$@"; } # Wrapper function

readonly R=$'\033[0m'      # Reset
readonly B=$'\033[1m'      # Bold
readonly I=$'\033[3m'      # Italic
readonly U=$'\033[4m'      # Underline
readonly S=$'\033[9m'      # Strikethrough
readonly D=$'\033[2m'      # Dim

# Authentic Monokai color palette (RGB)
readonly W=$'\033[38;2;248;248;242m'   # #F8F8F2 - White (bold text, H1)
readonly Y=$'\033[38;2;230;219;116m'   # #E6DB74 - Yellow (strings, italic)
readonly G=$'\033[38;2;166;226;46m'    # #A6E22E - Green (code, functions)
readonly O=$'\033[38;2;253;151;31m'    # #FD971F - Orange (parameters, bold+italic)
readonly M=$'\033[38;2;174;129;255m'   # #AE81FF - Purple (constants, H3)
readonly RED=$'\033[38;2;255;120;160m' # Very bright pink for maximum visibility
readonly C=$'\033[38;2;102;217;239m'   # #66D9EF - Blue (classes, links, borders)
readonly BL=$'\033[38;2;102;217;239m'  # #66D9EF - Blue (same as C for consistency)
readonly GR=$'\033[38;2;150;150;130m'  # Lighter gray for comments (more visible)

readonly BG=$'\033[48;2;39;40;34m'     # #272822 - Monokai background (inline code)
readonly BB=$'\033[48;2;39;40;34m'     # #272822 - Monokai background (code lang tag)

in_code=0
code_num=0

WIDTH=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}

repeat() {
    local char=$1 count=$2 result=""
    printf -v result '%*s' "$count"
    echo "${result// /$char}"
}

format_text() {
    local t="$1" m
    
    # Bold+Italic: ***text*** (must be before ** and *)
    while [[ $t =~ \*\*\*([^*]+)\*\*\* ]]; do
        m="${BASH_REMATCH[0]}"
        t="${t/"$m"/${B}${I}${O}${BASH_REMATCH[1]}${R}}"
    done
    
    # Bold: **text** or __text__
    while [[ $t =~ \*\*([^*]+)\*\* ]]; do
        m="${BASH_REMATCH[0]}"
        t="${t/"$m"/${B}${RED}${BASH_REMATCH[1]}${R}}"
    done
    
    while [[ $t =~ __([^_]+)__ ]]; do
        m="${BASH_REMATCH[0]}"
        t="${t/"$m"/${B}${RED}${BASH_REMATCH[1]}${R}}"
    done
    
    # Italic: *text* or _text_
    while [[ $t =~ \*([^*]+)\* ]]; do
        m="${BASH_REMATCH[0]}"
        t="${t/"$m"/${I}${Y}${BASH_REMATCH[1]}${R}}"
    done
    
    while [[ $t =~ _([^_]+)_ ]]; do
        m="${BASH_REMATCH[0]}"
        t="${t/"$m"/${I}${Y}${BASH_REMATCH[1]}${R}}"
    done
    
    # Strikethrough: ~~text~~
    while [[ $t =~ ~~([^~]+)~~ ]]; do
        m="${BASH_REMATCH[0]}"
        t="${t/"$m"/${S}${GR}${BASH_REMATCH[1]}${R}}"
    done
    
    # Inline code: `text`
    while [[ $t =~ \`([^\`]+)\` ]]; do
        m="${BASH_REMATCH[0]}"
        t="${t/"$m"/${BG}${RED} ${BASH_REMATCH[1]} ${R}}"
    done
    
    echo "$t"
}

inline() {
    local t="$1" m link_text placeholder
    local -a replacements=()
    local placeholder_idx=0
    local PH=$'\x1F'  # ASCII Unit Separator - won't be in normal text
    
    # HTML links with bold: <a href="url"><b>text</b></a> - MUST be before plain <b> tags!
    while [[ $t =~ \<a[[:space:]]+href=\"([^\"]+)\"\>\<b\>([^\<]+)\</b\>\</a\> ]]; do
        m="${BASH_REMATCH[0]}"
        placeholder="${PH}${placeholder_idx}${PH}"
        replacements[$placeholder_idx]="${B}${M}${U}${BASH_REMATCH[2]}${R} ${G}→${R} ${G}${BASH_REMATCH[1]}${R}"
        t="${t/"$m"/$placeholder}"
        ((placeholder_idx++))
    done
    
    # HTML links: <a href="url">text</a>
    while [[ $t =~ \<a[[:space:]]+href=\"([^\"]+)\"\>([^\<]+)\</a\> ]]; do
        m="${BASH_REMATCH[0]}"
        placeholder="${PH}${placeholder_idx}${PH}"
        replacements[$placeholder_idx]="${B}${M}${U}${BASH_REMATCH[2]}${R} ${G}→${R} ${G}${BASH_REMATCH[1]}${R}"
        t="${t/"$m"/$placeholder}"
        ((placeholder_idx++))
    done
    
    # HTML bold tags: <b>text</b>
    while [[ $t =~ \<b\>([^\<]+)\</b\> ]]; do
        m="${BASH_REMATCH[0]}"
        placeholder="${PH}${placeholder_idx}${PH}"
        replacements[$placeholder_idx]="${B}${RED}${BASH_REMATCH[1]}${R}"
        t="${t/"$m"/$placeholder}"
        ((placeholder_idx++))
    done
    
    # Footnote references: [^1] - MUST be before other bracket patterns!
    while [[ $t =~ \[\^([0-9]+)\] ]]; do
        m="${BASH_REMATCH[0]}"
        placeholder="${PH}${placeholder_idx}${PH}"
        replacements[$placeholder_idx]="${M}[${BASH_REMATCH[1]}]${R}"
        t="${t/"$m"/$placeholder}"
        ((placeholder_idx++))
    done
    
    # Linked images: [![alt](img-url)](link-url) - MUST be first!
    while [[ $t =~ \[!\[([^]]*)\]\(([^\)]+)\)\]\(([^\)]+)\) ]]; do
        m="${BASH_REMATCH[0]}"
        placeholder="${PH}${placeholder_idx}${PH}"
        replacements[$placeholder_idx]="${M}${U}🖼  ${BASH_REMATCH[1]}${R} ${BL}→${R} ${BL}${BASH_REMATCH[3]}${R}"
        t="${t/"$m"/$placeholder}"
        ((placeholder_idx++))
    done
    
    # Images: ![alt](url)
    while [[ $t =~ !\[([^]]*)\]\(([^\)]+)\) ]]; do
        m="${BASH_REMATCH[0]}"
        placeholder="${PH}${placeholder_idx}${PH}"
        replacements[$placeholder_idx]="${M}🖼  ${BASH_REMATCH[1]}${R} ${D}${C}[${BASH_REMATCH[2]}]${R}"
        t="${t/"$m"/$placeholder}"
        ((placeholder_idx++))
    done
    
    # Links: [text](url) - Format the link text first!
    while [[ $t =~ \[([^]]+)\]\(([^\)]+)\) ]]; do
        m="${BASH_REMATCH[0]}"
        link_text=$(format_text "${BASH_REMATCH[1]}")
        placeholder="${PH}${placeholder_idx}${PH}"
        replacements[$placeholder_idx]="${B}${M}${U}${link_text}${R} ${G}→${R} ${G}${BASH_REMATCH[2]}${R}"
        t="${t/"$m"/$placeholder}"
        ((placeholder_idx++))
    done
    
    # Format remaining text (not in links/images)
    t=$(format_text "$t")
    
    # Restore placeholders
    for ((i=0; i<placeholder_idx; i++)); do
        t="${t//${PH}${i}${PH}/${replacements[$i]}}"
    done
    
    echo "$t"
}

render() {
    local input="$1" line prev_empty=1
    
    [[ -f "$input" ]] || input="/dev/stdin"
    
    while IFS= read -r line; do
        # Code blocks: ```lang (with optional leading whitespace)
        if [[ $line =~ ^[[:space:]]*\`\`\`(.*)$ ]]; then
            if ((in_code == 0)); then
                in_code=1
                code_num=0
                local lang="${BASH_REMATCH[1]}"
                lang="${lang# }"  # Trim leading space
                ((prev_empty == 0)) && echo ""
                [[ -n $lang ]] && echo "${BB}${W} $lang ${R}"
                echo "${D}${C}┌$(repeat ─ $((WIDTH-2)))┐${R}"
            else
                echo "${D}${C}└$(repeat ─ $((WIDTH-2)))┘${R}"
                in_code=0
            fi
            continue
        fi
        
        if ((in_code == 1)); then
            ((code_num++))
            local num=$(printf "%3d" $code_num)
            if [[ $line =~ ^[[:space:]]*# ]] || [[ $line =~ ^[[:space:]]*// ]]; then
                echo "${D}${C}${num}${R} ${D}${C}│${R} ${GR}${line}${R}"
            else
                echo "${D}${C}${num}${R} ${D}${C}│${R} ${G}${line}${R}"
            fi
            prev_empty=0
            continue
        fi
        
        if [[ -z $line ]]; then
            ((prev_empty == 0)) && echo ""
            prev_empty=1
            continue
        fi
        prev_empty=0
        
        # HTML details/summary tags
        if [[ $line =~ ^[[:space:]]*\<details\> ]]; then
            echo "${D}${C}▼ Details${R}"
            continue
        fi
        
        # Summary with content on same line
        if [[ $line =~ ^[[:space:]]*\<summary\>(.+)\</summary\> ]]; then
            echo "  ${B}${C}${BASH_REMATCH[1]}${R}"
            continue
        fi
        
        # Summary opening tag (content on next line)
        if [[ $line =~ ^[[:space:]]*\<summary\>(.*)$ ]]; then
            local content="${BASH_REMATCH[1]}"
            if [[ -n $content ]]; then
                echo "  ${B}${C}${content}${R}"
            fi
            continue
        fi
        
        # Summary closing tag
        if [[ $line =~ ^[[:space:]]*(.+)\</summary\>$ ]] || [[ $line =~ ^[[:space:]]*\</summary\>$ ]]; then
            local content="${BASH_REMATCH[1]}"
            if [[ -n $content ]]; then
                echo "  ${B}${C}${content}${R}"
            fi
            continue
        fi
        
        if [[ $line =~ ^[[:space:]]*\</details\> ]]; then
            continue
        fi
        
        # Strip paragraph and other HTML tags
        if [[ $line =~ ^[[:space:]]*\<p[[:space:]].*\>$ ]] || [[ $line =~ ^[[:space:]]*\</p\>$ ]]; then
            continue
        fi
        
        # Strip other HTML tags but keep content
        if [[ $line =~ ^[[:space:]]*\</?[a-z]+.*\>$ ]]; then
            continue
        fi
        
        # Footnote references: [^1]: text
        if [[ $line =~ ^\[\^([0-9]+)\]:[[:space:]](.+)$ ]]; then
            echo "${M}[${BASH_REMATCH[1]}]${R} ${D}$(inline "${BASH_REMATCH[2]}")${R}"
            continue
        fi
        
        # Headers: # through ######
        if [[ $line =~ ^(#{1,6})[[:space:]](.+)$ ]]; then
            local lvl=${#BASH_REMATCH[1]} txt="${BASH_REMATCH[2]}"
            echo ""
            case $lvl in
                1) echo "${B}${C}$(repeat ═ $WIDTH)${R}"
                   echo "${B}${RED}$txt${R}"
                   echo "${B}${C}$(repeat ═ $WIDTH)${R}" ;;
                2) echo "${B}${C}$txt${R}"
                   echo "${C}$(repeat ━ ${#txt})${R}" ;;
                3) echo "${B}${M}$txt${R}" ;;
                4) echo "${B}${O}▸ $txt${R}" ;;
                5) echo "${G}● $txt${R}" ;;
                6) echo "${D}${C}○ $txt${R}" ;;
            esac
            continue
        fi
        
        # Horizontal rule: --- or *** or ___
        [[ $line =~ ^[*_-]{3,}$ ]] && { echo "${D}${C}$(repeat ─ $WIDTH)${R}"; continue; }
        
        # Admonitions: !!! type "title" or ??? type "title"
        if [[ $line =~ ^(\?\?\?|!!![!]*)[[:space:]]+([a-z]+)([[:space:]]+\"([^\"]+)\")? ]]; then
            local marker="${BASH_REMATCH[1]}" type="${BASH_REMATCH[2]}" title="${BASH_REMATCH[4]}"
            [[ -z $title ]] && title="$type"
            local icon="ⓘ" color="$C"
            case "$type" in
                danger|error) icon="⚠" color="$RED" ;;
                warning) icon="⚡" color="$O" ;;
                success|tip) icon="✓" color="$G" ;;
                info|note) icon="ⓘ" color="$BL" ;;
            esac
            echo "${B}${color}${icon} ${title}${R}"
            continue
        fi
        
        # Blockquote: > text
        if [[ $line =~ ^\>[[:space:]]?(.*)$ ]]; then
            echo "${O}┃${R} ${I}${O}$(inline "${BASH_REMATCH[1]}")${R}"
            continue
        fi
        
        # Task list: - [ ] or - [x]
        if [[ $line =~ ^[[:space:]]*[-*][[:space:]]\[([[:space:]xX])\][[:space:]](.+)$ ]]; then
            local chk="${BASH_REMATCH[1]}" txt="${BASH_REMATCH[2]}"
            if [[ $chk =~ [xX] ]]; then
                echo "  ${G}✓${R} ${D}$(inline "$txt")${R}"
            else
                echo "  ${BL}○${R} $(inline "$txt")"
            fi
            continue
        fi
        
        # Ordered list: 1. item
        if [[ $line =~ ^([[:space:]]*)(([0-9]+)\.)[[:space:]](.+)$ ]]; then
            local ind="${BASH_REMATCH[1]}" num="${BASH_REMATCH[3]}" txt="${BASH_REMATCH[4]}"
            echo "${ind}${C}${num}.${R} $(inline "$txt")"
            continue
        fi
        
        # Unordered list: - item or * item
        if [[ $line =~ ^([[:space:]]*)[-*+][[:space:]](.+)$ ]]; then
            local ind="${BASH_REMATCH[1]}" txt="${BASH_REMATCH[2]}"
            local bullet="●"
            case $(( (${#ind} / 2) % 3 )) in
                1) bullet="○" ;;
                2) bullet="▪" ;;
            esac
            echo "${ind}${C}${bullet}${R} $(inline "$txt")"
            continue
        fi
        
        # Tables: | col | col |
        if [[ $line =~ ^\|.*\|$ ]]; then
            if [[ $line =~ ^\|[[:space:]:|-]+\|$ ]]; then
                echo "${C}$(repeat ─ $WIDTH)${R}"
            else
                line="${line#|}" line="${line%|}"
                local output="${C}│${R}" rest="$line" cell
                while [[ $rest =~ ^([^|]*)\|(.*)$ ]]; do
                    cell="${BASH_REMATCH[1]}"
                    rest="${BASH_REMATCH[2]}"
                    output+=" $(inline "$cell") ${C}│${R}"
                done
                # Handle last cell (no trailing |)
                [[ -n $rest ]] && output+=" $(inline "$rest") ${C}│${R}"
                echo "$output"
            fi
            continue
        fi
        
        inline "$line"
    done < "$input"
}

help() {
    cat << 'EOF'
BUSYMD - Markdown Viewer for Busybox and Beyond

USAGE:
    busymd FILE.md          View markdown file with pager
    busymd --no-pager FILE  Direct output without pager
    cat FILE | busymd       Read from stdin

NAVIGATION (in less):
    g / G         Go to beginning / end of file
    j / k         Scroll down / up one line
    d / u         Scroll down / up half page
    f / b         Scroll down / up full page
    Space         Scroll down full page

SEARCH:
    /pattern      Search forward
    ?pattern      Search backward
    n / N         Next / previous match

OTHER:
    q             Quit
    h             Help

EOF
}

busymd() {
    local use_pager=1 input=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help) help; exit 0 ;;
            --no-pager) use_pager=0; shift ;;
            *) input="$1"; break ;;
        esac
    done
    
    [[ -z $input ]] && { [[ -p /dev/stdin ]] && input="/dev/stdin" || { help; exit 0; }; }
    [[ -f $input ]] || [[ $input == /dev/stdin ]] || { echo "Error: File not found: $input" >&2; exit 1; }
    
    if ((use_pager == 1)) && [[ -t 1 ]]; then
        render "$input" | less -R -F -X -i -M
    else
        render "$input"
    fi
}

[[ ${BASH_SOURCE[0]} == "$0" ]] && busymd "$@"
