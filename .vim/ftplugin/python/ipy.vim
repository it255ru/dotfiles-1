
"
" A two-way integration between Vim and IPython. 
"
" Using this plugin, you can send lines or whole files for IPython to execute,
" and also get back object introspection and word completions in Vim, like
" what you get with: object?<enter> object.<tab> in IPython
"
" -----------------
" Quickstart Guide:
" -----------------
" Start ipython qtconsole and copy the connection string.
" Source this file, which provides new IPython command
"   :source ipy.vim  
"   :IPythonClipboard   
"   (or :IPythonXSelection if you're using X11 without having to copy)
"
" written by Paul Ivanov (http://pirsquared.org)
python << EOF
reselect = False            # reselect lines after sending from Visual mode
show_execution_count = True # wait to get numbers for In[43]: feedback?
monitor_subchannel = True   # update vim-ipython 'shell' on every send?
run_flags= "-i"             # flags to for IPython's run magic when using <F5>

import vim
import sys

# get around unicode problems when interfacing with vim
vim_encoding=vim.eval('&encoding')

try:
    sys.stdout.flush
except AttributeError:
    # IPython complains if stderr and stdout don't have flush
    # this is fixed in newer version of Vim
    class WithFlush(object):
        def __init__(self,noflush):
            self.write=noflush.write
            self.writelines=noflush.writelines
        def flush(self):pass
    sys.stdout = WithFlush(sys.stdout)
    sys.stderr = WithFlush(sys.stderr)



ip = '127.0.0.1'
try:
    km
except NameError:
    km = None

def km_from_string(s):
    """create kernel manager from IPKernelApp string
    such as '--shell=47378 --iopub=39859 --stdin=36778 --hb=52668'
    """
    from IPython.zmq.blockingkernelmanager import BlockingKernelManager, Empty
    from IPython.config.loader import KeyValueConfigLoader
    from IPython.zmq.kernelapp import kernel_aliases
    global km,send,Empty
    # vim interface currently only deals with existing kernels
    s = s.replace('--existing','')
    loader = KeyValueConfigLoader(s.split(), aliases=kernel_aliases)
    cfg = loader.load_config()['KernelApp']
    try:
        km = BlockingKernelManager(
            shell_address=(ip, cfg['shell_port']),
            sub_address=(ip, cfg['iopub_port']),
            stdin_address=(ip, cfg['stdin_port']),
            hb_address=(ip, cfg['hb_port']))
    except KeyError,e:
        echo(":IPython " +s + " failed", "Info")
        echo("^-- failed --"+e.message.replace('_port','')+" not specified", "Error")
        return
    km.start_channels()
    send = km.shell_channel.execute
    return km

def echo(arg,style="Question"):
    try:
        vim.command("echohl %s" % style)
        vim.command("echom \"%s\"" % arg.replace('\"','\\\"'))
        vim.command("echohl None")
    except vim.error:
        print "-- %s" % arg

def disconnect():
    "disconnect kernel manager"
    # XXX: make a prompt here if this km owns the kernel
    pass

def get_doc(word):
    if km is None:
        return ["Not connected to IPython, cannot query \"%s\"" %word]
    msg_id = km.shell_channel.object_info(word)
    doc = get_doc_msg(msg_id)
    # get around unicode problems when interfacing with vim
    return [d.encode(vim_encoding) for d in doc]

import re
# from http://serverfault.com/questions/71285/in-centos-4-4-how-can-i-strip-escape-sequences-from-a-text-file
strip = re.compile('\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]')
def strip_color_escapes(s):
    return strip.sub('',s)
    
def get_doc_msg(msg_id):
    n = 13 # longest field name (empirically)
    b=[]
    try:
        content = get_child_msg(msg_id)['content']
    except Empty:
        # timeout occurred
        return ["no reply from IPython kernel"]

    if not content['found']:
        return b

    for field in ['type_name','base_class','string_form','namespace',
            'file','length','definition','source','docstring']:
        c = content.get(field,None)
        if c:
            if field in ['definition']:
                c = strip_color_escapes(c).rstrip()
            s = field.replace('_',' ').title()+':'
            s = s.ljust(n)
            if c.find('\n')==-1:
                b.append(s+c)
            else:
                b.append(s)
                b.extend(c.splitlines())
    return b

def get_doc_buffer(level=0):
    # empty string in case vim.eval return None
    word = vim.eval('expand("<cfile>")') or ''
    doc = get_doc(word)
    if len(doc) ==0:
        echo(word+" not found","Error")
        return
    # close any currently open preview windows
    vim.command('pcl')
    # documentation buffer name is same as the query made to ipython
    vim.command('new '+word)
    vim.command('setlocal pvw modifiable noro')
    # doc window quick quit keys: 'q' and 'escape'
    vim.command('map <buffer> q :q<CR>')
    # Known issue: to enable the use of arrow keys inside the terminal when
    # viewing the documentation, comment out the next line
    vim.command('map <buffer> <Esc> :q<CR>')
    # and uncomment this line (which will work if you have a timoutlen set)
    #vim.command('map <buffer> <Esc><Esc> :q<CR>')
    b = vim.current.buffer
    b[:] = None
    b[:] = doc
    vim.command('setlocal nomodified bufhidden=wipe')
    #vim.command('setlocal previewwindow nomodifiable nomodified ro')
    #vim.command('set previewheight=%d'%len(b))# go to previous window
    vim.command('resize %d'%len(b))
    #vim.command('pcl')
    #vim.command('pedit doc')
    #vim.command('normal ') # go to previous window

def update_subchannel_msgs(debug=False):
    msgs = km.sub_channel.get_msgs()
    if debug:
        #try:
        #    vim.command("b debug_msgs")
        #except vim.error:
        #    vim.command("new debug_msgs")
        #finally:
        db = vim.current.buffer
    else:
        db = []
    startedin_vimipython = vim.current.buffer.name.endswith('vim-ipython')
    if not startedin_vimipython:
        vim.command("pcl")
        vim.command("silent pedit vim-ipython")
        vim.command("normal P") #switch to preview window
    # subchannel window quick quit key 'q'
    vim.command('map <buffer> q :q<CR>')
    vim.command("set bufhidden=hide buftype=nofile ft=python")
    
    #syntax highlighting for python prompt
    # QtConsole In[] is blue, but I prefer the oldschool green
    # since it makes the vim-ipython 'shell' look like the holidays!
    #vim.command("hi Blue ctermfg=Blue guifg=Blue")
    vim.command("hi Green ctermfg=Green guifg=Green")
    vim.command("hi Red ctermfg=Red guifg=Red")
    vim.command("syn keyword Green 'In\ []:'")
    vim.command("syn match Green /^In \[[0-9]*\]\:/")
    vim.command("syn match Red /^Out\[[0-9]*\]\:/")
    b = vim.current.buffer
    for m in msgs:
        #db.append(str(m).splitlines())
        s = ''
        if 'msg_type' not in m['header']:
            # debug information
            #echo('skipping a message on sub_channel','WarningMsg')
            #echo(str(m))
            continue
        elif m['header']['msg_type'] == 'status':
            continue
        elif m['header']['msg_type'] == 'stream':
            s = strip_color_escapes(m['content']['data'])
        elif m['header']['msg_type'] == 'pyout':
            s = "Out[%d]: " % m['content']['execution_count']
            s += m['content']['data']['text/plain']
        elif m['header']['msg_type'] == 'pyin':
            # TODO: the next line allows us to resend a line to ipython if
            # %doctest_mode is on. In the future, IPython will send the
            # execution_count on subchannel, so this will need to be updated
            # once that happens
            s = "\nIn [00]: "
            s += m['content']['code'].strip()
        elif m['header']['msg_type'] == 'pyerr':
            c = m['content']
            s = "\n".join(map(strip_color_escapes,c['traceback']))
            s += c['ename'] + ":" + c['evalue']
        if s.find('\n') == -1:
            # somewhat ugly unicode workaround from 
            # http://vim.1045645.n5.nabble.com/Limitations-of-vim-python-interface-with-respect-to-character-encodings-td1223881.html
            if isinstance(s,unicode):
                s=s.encode(vim_encoding)
            b.append(s)
        else:
            try:
                b.append(s.splitlines())
            except:
                b.append([l.encode(vim_encoding) for l in s.splitlines()])
    vim.command('normal G') # go to the end of the file
    if not startedin_vimipython:
        vim.command('normal p') # go back to where you were
    
def get_child_msg(msg_id):
    # XXX: message handling should be split into its own process in the future
    while True:
        # get_msg will raise with Empty exception if no messages arrive in 1 second
        m= km.shell_channel.get_msg(timeout=1)
        if m['parent_header']['msg_id'] == msg_id:
            break
        else:
            #got a message, but not the one we were looking for
            echo('skipping a message on shell_channel','WarningMsg')
    return m
            
def print_prompt(prompt,msg_id=None):
    """Print In[] or In[42] style messages"""
    global show_execution_count
    if show_execution_count and msg_id:
        # wait to get message back from kernel
        try:
            child = get_child_msg(msg_id)
            count = child['content']['execution_count']
            echo("In[%d]: %s" %(count,prompt))
        except Empty:
            echo("In[]: %s (no reply from IPython kernel)" % prompt)
    else:
        echo("In[]: %s" % prompt)

def with_subchannel(f):
    "conditionally monitor subchannel"
    def f_with_update():
        try:
            f()
            if monitor_subchannel:
                update_subchannel_msgs()
        except AttributeError: #if km is None
            echo("not connected to IPython", 'Error')
    return f_with_update

@with_subchannel
def run_this_file():
    msg_id = send('run %s %s' % (run_flags, repr(vim.current.buffer.name),))
    print_prompt("In[]: run %s %s" % (run_flags, repr(vim.current.buffer.name)),msg_id)

@with_subchannel
def run_this_line():
    msg_id = send(vim.current.line)
    print_prompt(vim.current.line, msg_id)

@with_subchannel
def run_these_lines():
    r = vim.current.range
    lines = "\n".join(vim.current.buffer[r.start:r.end+1])
    msg_id = send(lines)
    #alternative way of doing this in more recent versions of ipython
    #but %paste only works on the local machine
    #vim.command("\"*yy")
    #send("'%paste')")
    #reselect the previously highlighted block
    vim.command("normal gv")
    if not reselect:
        vim.command("normal ")

    #vim lines start with 1
    #print "lines %d-%d sent to ipython"% (r.start+1,r.end+1)
    prompt = "lines %d-%d "% (r.start+1,r.end+1)
    print_prompt(prompt,msg_id)

def dedent_run_this_line():
    vim.command("left")
    run_this_line()
    vim.command("undo")

def dedent_run_these_lines():
    vim.command("'<,'>left")
    run_these_lines()
    vim.command("undo")
    
#def set_this_line():
#    # not sure if there's a way to do this, since we have multiple clients
#    send("get_ipython().shell.set_next_input(\'%s\')" % vim.current.line.replace("\'","\\\'"))
#    #print "line \'%s\' set at ipython prompt"% vim.current.line
#    echo("line \'%s\' set at ipython prompt"% vim.current.line,'Statement')


def toggle_reselect():
    global reselect
    reselect=not reselect
    print "F9 will%sreselect lines after sending to ipython"% (reselect and " " or " not ")

#def set_breakpoint():
#    send("__IP.InteractiveTB.pdb.set_break('%s',%d)" % (vim.current.buffer.name,
#                                                        vim.current.window.cursor[0]))
#    print "set breakpoint in %s:%d"% (vim.current.buffer.name, 
#                                      vim.current.window.cursor[0])
#    
#def clear_breakpoint():
#    send("__IP.InteractiveTB.pdb.clear_break('%s',%d)" % (vim.current.buffer.name,
#                                                          vim.current.window.cursor[0]))
#    print "clearing breakpoint in %s:%d" % (vim.current.buffer.name,
#                                            vim.current.window.cursor[0])
#
#def clear_all_breakpoints():
#    send("__IP.InteractiveTB.pdb.clear_all_breaks()");
#    print "clearing all breakpoints"
#
#def run_this_file_pdb():
#    send(' __IP.InteractiveTB.pdb.run(\'execfile("%s")\')' % (vim.current.buffer.name,))
#    #send('run -d %s' % (vim.current.buffer.name,))
#    echo("In[]: run -d %s (using pdb)" % vim.current.buffer.name)

EOF

fun! <SID>toggle_send_on_save()
    if exists("s:ssos") && s:ssos == 0
        let s:ssos = 1
        au BufWritePost *.py :py run_this_file()
        echo "Autosend On"
    else
        let s:ssos = 0
        au! BufWritePost *.py
        echo "Autosend Off"
    endif
endfun

" Allow custom mappings
if !exists('g:ipy_perform_mappings')
    let g:ipy_perform_mappings = 1
endif
if g:ipy_perform_mappings != 0
    map <silent> <F5> :python run_this_file()<CR>
    map <silent> <S-F5> :python run_this_line()<CR>
    map <silent> <F9> :python run_these_lines()<CR>
    map <silent> <leader>h :py get_doc_buffer()<CR>
    map <silent> <leader>s :py update_subchannel_msgs(); echo("vim-ipython shell updated",'Operator')<CR>
    map <silent> <S-F9> :python toggle_reselect()<CR>
    "map <silent> <C-F6> :python send('%pdb')<CR>
    "map <silent> <F6> :python set_breakpoint()<CR>
    "map <silent> <s-F6> :python clear_breakpoint()<CR>
    "map <silent> <F7> :python run_this_file_pdb()<CR>
    "map <silent> <s-F7> :python clear_all_breaks()<CR>
    imap <C-F5> <C-O><F5>
    imap <S-F5> <C-O><S-F5>
    imap <silent> <F5> <C-O><F5>
    map <C-F5> :call <SID>toggle_send_on_save()<CR>

    "pi custom
    map <silent> <C-Return> :python run_this_file()<CR>
    map <silent> <C-p> :python set_this_line()<CR>
    map <silent> <M-c> I#<ESC>
    vmap <silent> <M-c> I#<ESC>
    map <silent> <M-C> :s/^\([ \t]*\)#/\1/<CR>
    vmap <silent> <M-C> :s/^\([ \t]*\)#/\1/<CR>
endif

command! -nargs=+ IPython :py km_from_string("<args>")
command! -nargs=0 IPythonClipboard :py km_from_string(vim.eval('@+'))
command! -nargs=0 IPythonXSelection :py km_from_string(vim.eval('@*'))

function! IPythonBalloonExpr()
python << endpython
word = vim.eval('v:beval_text')
reply = get_doc(word)
vim.command("let l:doc = %s"% reply)
endpython
return l:doc
endfunction
if has('balloon_eval')
    set bexpr=IPythonBalloonExpr()
    set ballooneval
endif

fun! CompleteIPython(findstart, base)
	  if a:findstart
	    " locate the start of the word
	    let line = getline('.')
	    let start = col('.') - 1
	    while start > 0 && line[start-1] =~ '\k\|\.' "keyword
	      let start -= 1
	    endwhile
        echo start
	    return start
	  else
	    " find months matching with "a:base"
	    let res = []
        python << endpython
base = vim.eval("a:base")
findstart = vim.eval("a:findstart")
msg_id = km.shell_channel.complete(base, vim.current.line, vim.eval("col('.')"))
try:
    m = get_child_msg(msg_id)
    matches = m['content']['matches']
    matches.insert(0,base) # the "no completion" version
    # we need to be careful with unicode, because we can have unicode
    # completions for filenames (for the %run magic, for example). So the next
    # line will fail on those:
    #completions= [str(u) for u in matches]
    # because str() won't work for non-ascii characters
    # and we also have problems with unicode in vim, hence the following:
    completions = [s.encode(vim_encoding) for s in matches]
except Empty:
    echo("no reply from IPython kernel")
    completions=['']
## Additionally, we have no good way of communicating lists to vim, so we have
## to turn in into one long string, which can be problematic if e.g. the
## completions contain quotes. The next line will not work if some filenames
## contain quotes - but if that's the case, the user's just asking for
## it, right?
#completions = '["'+ '", "'.join(completions)+'"]'
#vim.command("let completions = %s" % completions)
## An alternative for the above, which will insert matches one at a time, so
## if there's a problem with turning a match into a string, it'll just not
## include the problematic match, instead of not including anything. There's a
## bit more indirection here, but I think it's worth it
for c in completions:
    vim.command('call add(res,"'+c+'")')
endpython
        "call extend(res,completions) 
	    return res
	  endif
	endfun
set completefunc=CompleteIPython
