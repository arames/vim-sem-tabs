" Author: Alexandre Rames <alexandre@uop.re>
" License: This file is placed in the public domain.
" Version: None. This plugin is work in progress. See the git logs for history.
"
" SemTabs - Indent with tabs, align with spaces.
"
" *WARNING*: This plugin is not bug free and is known to break three-piece
" comments (see comments below). Please report bugs and issues.
"
" This plugin effectively differentiates between alignment and semantic
" indentation. Tabs are only inserted at the beginning of lines for semantic
" indentation.  Elsewhere, spaces are used as if the `expandtab` setting was
" set. With this scheme, users can use their preferred `tabstop` setting and the
" alignment will stay coherent.
"
" The goals of this plugin are:
" - Enable semantic indentation when the `expandtab` setting is unset.
" - Provide additional features for the <Tab> key:
"   - Hitting <Tab> at the start of a line performs smart-indentation.
"   - Hitting <Tab> within whitespace characters jumps to the next
"     non-whitespace character
" - Do not break built-in features. In particular:
"   - Undo actions should still work correctly.
"   - C-style comments automatic features should still work.
"     *WARNING*: the plugin currently breaks automatic closing of C-style
"     comments (and probably generally of three-piece comments, see
"     `:help format-comments`). I could not find a way to both preserve undo and
"     automatic commenting features.
"
" I started writing this plugin after I found that the similar SmartTabs plugin
" (http://www.vim.org/scripts/script.php?script_id=231) was not working or
" breaking too many things in my editing flow, in particular the undo and
" automatic commenting features. Trying to fix things in place was
" taking too much time, so I wrote this plugin from scratch, sharing some of the
" ideas used by SmartTabs.


if exists("g:loaded_sem_tabs")
  finish
endif
let g:loaded_sem_tabs = 1


" When set (by default), this causes the plugin to delete trailing whitespaces
" on the current line when pressing 'Enter'.
let g:sem_tabs_delete_whitespace_on_newline = 1

" When set and the cursor is positionned in some initial whitespace at the start
" of a line, hitting <Tab> inserts the full correct indentation for the line.
if !exists("g:sem_tabs_one_tab_indent")
  let g:sem_tabs_one_tab_indent = 1
endif
" When set and the cursor is positionned within whitespace characters, hitting
" <Tab> will cause the cursor to move to the first non-whitespace character
" after the cursor on the line (or to the end of the line.
if !exists("g:sem_tabs_tab_space_jump")
  let g:sem_tabs_tab_space_jump = 1
endif

" Internal configuration.
" TODO: Document this.
if !exists("g:sem_tabs_internal_step")
  let g:sem_tabs_internal_step = 80
endif




" Get the indentation width for the current line. The width here is the number
" of 'space blocks' that should appear at the start of the line. This relies on
" VIM's built-in automatic indentation features.
function! GetLineAutoIndentWidth(line_number)
  if &indentexpr != ''
    let v:lnum = a:line_number
    sandbox exe 'let indent_width = ' . &indentexpr
    if indent_width == -1
      return indent(a:line_number - 1)
    endif
  elseif &cindent
    return cindent(a:line_number)
  elseif &lisp
    return lispindent(a:line_number)
  elseif &autoindent
    return indent(a:line_number)
  else
    return 0
  endif
endfunction


" Return indentation information for the specified line.
" This function returns indentation information for the specified line as a list
" [valid, indent_tabs, indent_spaces].
" Description of the elements returned:
" - indent_tabs: The number of semantic indentation levels. It also represents
"   the number of tabs at the beginning of the indentation string.
" - indent_spaces: The number of spaces required for alignment. This number of
"   spaces is present at the end of the indentation string.
function! IndentationForLine(line_number)
  " Don't do anything if tabs are expanded to spaces or if no automatic
  " indentation feature is on.
  if &expandtab || !(&indentexpr || &cindent || &lisp || &autoindent)
    return [0, 0, 0]
  endif

  " Find out how many tabs and how many spaces we need.
  " We artificially increase the settings for tabwidth settings to distinguish
  " between indentation and code. This is really not clean.
  let saved_tabstop=&tabstop
  let saved_shiftwidth=&shiftwidth

  try
    let &tabstop=g:sem_tabs_internal_step
    let &shiftwidth=g:sem_tabs_internal_step
    let l:indent_width = GetLineAutoIndentWidth(a:line_number)

  finally
    " Make sure to restore the user settings.
    let &tabstop = saved_tabstop
    let &shiftwidth = saved_shiftwidth
  endtry

  let l:indent_tabs = l:indent_width / g:sem_tabs_internal_step
  let l:indent_spaces = l:indent_width % g:sem_tabs_internal_step

  return [1, l:indent_tabs, l:indent_spaces]
endfunction


" Build a string for the specified indentation.
function! IndentationString(indent_tabs, indent_spaces)
  return repeat("\<Tab>", a:indent_tabs) . repeat(' ', a:indent_spaces)
endfunction


function! MoveCursorAfterIndentation(line_number, indent_tabs, indent_spaces)
  call setpos('.', [0, a:line_number, a:indent_tabs + a:indent_spaces + 1, 0])
endfunction


function! DeleteTrailingWhitespaces(line_number)
  let l:text = getline(a:line_number)
  call setline(a:line_number, substitute(getline(a:line_number), "\\s*$", "", "e"))
endfunction


" Reindent the specified line.
" After this function, the cursor may be left in a wrong position on the line.
function! ReindentLine(line_number)
  let [l:valid, l:indent_tabs, l:indent_spaces] = IndentationForLine(a:line_number)
  if l:valid
    call setline(a:line_number, substitute(getline(a:line_number), '^\s*', IndentationString(l:indent_tabs, l:indent_spaces), ''))
  endif
  return [l:valid, l:indent_tabs, l:indent_spaces]
endfunction


" The cursor should not appear to move on the screen when this function is run.
" Handle tab insertion.
function! InsertTab()
  let l:current_line = getline('.')

  let l:start_string = strpart(l:current_line, 0, col('.'))
  let l:current_column = virtcol('.')

  " Handle situations where the cursor is at the start of the line.
  if  l:start_string =~ '^\s*$'
    let [l:valid, l:indent_tabs, l:indent_spaces] = IndentationForLine(line('.'))
    if l:valid && l:current_column < l:indent_tabs * &tabstop + l:indent_spaces
      if g:sem_tabs_one_tab_indent
        call ReindentLine(line('.'))
        call MoveCursorAfterIndentation(line('.'), l:indent_tabs, + l:indent_spaces)
        return ''
      else
        return "\<Tab>"
      endif
    endif
  endif

  if g:sem_tabs_tab_space_jump
    " If there is whitespace after the cursor, move the cursor to the end of this
    " whitespace sequence.
    let l:cursor_position = getpos('.')
    let l:first_non_s_after_cursor = match(l:current_line, '\S', l:cursor_position[2])
    let l:end_column = virtcol('$') - 1
    if l:current_column < l:end_column  && l:cursor_position[2] != l:first_non_s_after_cursor
      let l:cursor_position[2] = l:first_non_s_after_cursor + 1
      call setpos('.', l:cursor_position)
      return ''
    endif
  endif

  return repeat(" ", &tabstop - l:current_column % &tabstop)
endfunction


" Override keys and commands that interact with indentation.

" TODO: Do we need to use `noremap`?


function! NormalCommandAndReindent(normal_command)
  " We append a '_' to preserve any special alignment introduced.
  execute "normal! " . a:normal_command . "_"
  call ReindentLine(line('.'))
  normal! $x
endfunction
nnoremap <silent> o :call NormalCommandAndReindent('o')<CR>a
nnoremap <silent> O :call NormalCommandAndReindent('O')<CR>a


function! DoNewLineHelper()
  let l:saved_pos = getpos('.')
  let l:saved_virt_column = virtcol('.')

  " Perform the reindentation
  call ReindentLine(line('.'))
  if g:sem_tabs_delete_whitespace_on_newline != 0
    call DeleteTrailingWhitespaces(line('.') - 1)
  endif

  " Now set the cursor to the right position.
  let [l:pos_buf, l:pos_line, l:pos_col, l:pos_off] = l:saved_pos
  let l:col = 1
  let l:end = col('$')
  call setpos('.', [l:pos_buf, l:pos_line, l:col, 0])
  while l:col <= l:end && virtcol('.') != l:saved_virt_column
    call setpos('.', [l:pos_buf, l:pos_line, l:col, 0])
    let l:col += 1
  endwhile
endfunction
inoremap <silent> <CR> <CR>_<C-o>:call DoNewLineHelper()<CR><BS>


function! TabHelper()
  return "\<C-r>=InsertTab()\<CR>"
endfunction
inoremap <silent> <expr> <Tab> TabHelper()


function! AlignmentOperator(type,...)
  let l:line_from = line("'[")
  let l:line = l:line_from
  let l:line_to = line("']")

  while l:line <= l:line_to
    call ReindentLine(l:line)
    let l:line += 1
  endwhile

  " Set the cursor to the same position the original '=' operator would set it
  " to.
  let [l:valid, l:u1, l:u2] = IndentationForLine(l:line_from)
  if l:valid
    call setpos('.', l:aligned_cursor_pos)
  endif
endfunction

function! AlignmentOperatorSingleLine()
  let [l:valid, l:indent_tabs, l:indent_spaces] = ReindentLine(line('.'))
  call MoveCursorAfterIndentation(line('.'), l:indent_tabs, l:indent_spaces)
endfunction

nnoremap <silent> = :set operatorfunc=AlignmentOperator<CR>g@
vnoremap <silent> = :<C-U>call AlignmentOperator(visualmode(), 1)<CR>
nnoremap <silent> == :call AlignmentOperatorSingleLine()<CR>

" Automatically delete unused indentation left on a line when exiting insert
" mode.
function! DeleteTrailingWhitespaceIfOption(line_number)
  " Delete the unused indentation if the settings require it.
  " Note that we do that even if we did not introduce the spaces.
  if ('cpo' !~ 'I')
    call DeleteTrailingWhitespaces(a:line_number)
  endif
endfunction

augroup SemTabDeleteUnusedIndentation
  au! InsertLeave * call DeleteTrailingWhitespaceIfOption(line('.'))
augroup END


" vim: ts=2 sw=2 et
