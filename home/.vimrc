syntax on | set nu mouse=a ai cin hls is sm ts=4 sw=4 noswf
set mp=clang++\ -Wall\ -Wextra\ -Werror\ -g\ -std=c++98\ *.cpp
au BufWritePost *.cpp,*.hpp silent make!| redraw! | cw
nn <F6> :!./a.out<CR>
nn <F5> :!gdb ./a.out<CR>
ino jk <Esc>






















