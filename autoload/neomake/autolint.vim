"=============================================================================
" FILE: autoload/neomake/autolint.vim
" AUTHOR: dojoteef
" License: MIT license
"=============================================================================
scriptencoding utf-8
let s:save_cpo = &cpoptions
set cpoptions&vim

function! neomake#autolint#update(bufinfo) abort
  " Write the temporary file
  silent! keepalt noautocmd call writefile(
        \ getline(1, '$'),
        \ a:bufinfo.tmpfile)

  " Run neomake in file mode with the autolint makers
  call neomake#utils#hook('NeomakeAutolint', {'bufnr': a:bufinfo.bufnr})
  call neomake#Make(1, a:bufinfo.makers)
endfunction

function! s:neomake_onchange(bufnr, delay) abort
  let l:bufinfo = neomake#autolint#buffer#get(a:bufnr)
  if empty(l:bufinfo)
    return
  endif

  let l:lasttimerid = l:bufinfo.timerid
  let l:bufinfo.timerid = -1
  if l:lasttimerid != -1
    call timer_stop(l:lasttimerid)
  endif

  let l:bufinfo.timerid = timer_start(a:delay,
        \ neomake#autolint#utils#function('s:neomake_tryupdate'))
endfunction

function! s:neomake_tryupdate(timerid) abort
  " Get the buffer info
  let l:bufinfo = neomake#autolint#buffer#get_from_timer(a:timerid)

  " Could not find the buffer associated with the timer
  if empty(l:bufinfo)
    return
  endif

  call neomake#autolint#update(l:bufinfo)
endfunction

"=============================================================================
" Public Functions: Functions that are called by plugin (auto)commands
"=============================================================================
function! neomake#autolint#Startup() abort
  " Define an invisible sign that can keep the sign column always showing
  execute 'sign define neomake_autolint_invisible'

  " Setup auto commands for managing the autolinting
  autocmd neomake_autolint BufWinEnter * call neomake#autolint#Setup()
  autocmd neomake_autolint VimLeavePre * call neomake#autolint#Removeall()
  autocmd neomake_autolint BufWipeout * call neomake#autolint#Remove(expand('<abuf>'))

  " Call setup on all the currently visible buffers
  let l:buflist = uniq(sort(tabpagebuflist()))
  for l:bufnr in l:buflist
    call neomake#autolint#Setup(l:bufnr)
  endfor
endfunction

function! neomake#autolint#Setup(...) abort
  " Must have a cache directory
  if empty(neomake#autolint#utils#cachedir())
    return
  endif

  let l:bufnr = a:0 ? a:1 : bufnr('%')
  if neomake#autolint#buffer#has(l:bufnr)
    return
  endif

  let l:makers = neomake#autolint#buffer#makers(l:bufnr)
  if len(l:makers) > 0
    " Create the autolint buffer
    let l:bufinfo = neomake#autolint#buffer#create(l:bufnr, l:makers)

    if neomake#autolint#config#Get('sign_column_always')
      execute 'sign place 999999 line=1 name=neomake_autolint_invisible buffer='.l:bufnr
    endif

    """"""""""""""""""""""""""""""""""""""""""""""""""""""""
    " Text Changed Handling
    """"""""""""""""""""""""""""""""""""""""""""""""""""""""
    autocmd! neomake_autolint * <buffer>
    call neomake#autolint#Toggle(0, bufnr('%'))

    " Run neomake on the initial load of the buffer to check for errors
    call neomake#utils#hook('NeomakeAutolintSetup', {'bufinfo': l:bufinfo})

    " BufWinEnter is a special case event since we have not setup autolinting
    " yet, so check if linting should occur on BufWinEnter and lint if needed.
    let l:events = neomake#autolint#config#Get('events')
    if has_key(l:events, 'BufWinEnter')
      let l:config = l:events['BufWinEnter']
      let l:delay = get(l:config, 'delay', neomake#autolint#config#Get('updatetime'))
      call s:neomake_onchange(l:bufnr, l:delay)
    endif
  endif
endfunction

function! neomake#autolint#Now(...) abort
  let l:bufnr = a:0 ? a:1 : bufnr('%')
  let l:bufinfo = neomake#autolint#buffer#get(l:bufnr)
  if empty(l:bufinfo)
    call neomake#utils#LoudMessage(printf('Cannot find buffer %d', l:bufnr))
    return
  endif

  call neomake#autolint#update(l:bufinfo)
endfunction

function! neomake#autolint#Toggle(all, ...) abort
  let l:group = 'neomake_autolint'
  let l:cmd = [l:group, 'BufWinEnter', '*']
  let l:enabled = exists('#'.join(l:cmd, '#'))

  if a:all
    if l:enabled
      call insert(l:cmd, 'autocmd!')
    else
      call insert(l:cmd, 'autocmd')
      call add(l:cmd, 'call neomake#autolint#Setup()')
    endif
    execute join(l:cmd)

    let l:bufnrs = neomake#autolint#buffer#bufnrs()
  elseif a:0
    let l:bufnrs = type(a:1) == type([]) ? a:1 : a:000

    " Convert to bufnr
    let l:bufnrs = map(copy(l:bufnrs), 'bufnr(v:val)')

    " Filter non-tracked/invalid buffers
    let l:expr = 'v:val > -1 && neomake#autolint#buffer#has(v:val)'
    let l:bufnrs = filter(l:bufnrs, l:expr)
  else
    return
  endif

  call neomake#utils#LoudMessage(printf(
        \ 'Toggling buffers: %s',
        \ join(l:bufnrs, ',')))

  let l:disable = (a:all && l:enabled)
  let l:events = neomake#autolint#config#Get('events')
  let l:default_delay = neomake#autolint#config#Get('updatetime')
  for l:bufnr in l:bufnrs
    let l:buffer = printf('<buffer=%d>', l:bufnr)

    for l:event in keys(l:events)
      let l:config = l:events[l:event]
      let l:delay = get(l:config, 'delay', l:default_delay)

      let l:cmd = ['neomake_autolint', l:event, l:buffer]
      if l:disable || exists(printf('#%s', join(l:cmd, '#')))
        call insert(l:cmd, 'autocmd!')
      else
        call insert(l:cmd, 'autocmd')
        call add(l:cmd, printf('call s:neomake_onchange(%d, %d)', l:bufnr, l:delay))
      endif

      call neomake#utils#DebugMessage(printf('Executing: %s', join(l:cmd)))
      execute join(l:cmd)
    endfor
  endfor
endfunction

function! neomake#autolint#Remove(bufnr) abort
  call neomake#utils#LoudMessage(printf('Removing buffer: %s', string(a:bufnr)))
  call neomake#autolint#buffer#clear(a:bufnr)
endfunction

function! neomake#autolint#Removeall() abort
  call neomake#autolint#buffer#clear()
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
" __END__
" vim: expandtab softtabstop=2 shiftwidth=2 foldmethod=marker
