# KVS_SERVER

> Is a VERY basic key-value store written in nim language ([http://nim-lang.org/](http://nim-lang.org/))

This is my first nim program. So please forgive me if some parts of code are ugly (: All critics that can help improving me are welcome !

The server part is inspired by the work of Göran Krampe :
[Nim Socket Server](http://goran.krampe.se/2014/10/25/nim-socketserver/)

## How to compile

1. Install the nim compiler
2. Clone this git repo
3. just type `make` in your terminal

## How to use

1. First run the server : ./kvs_server
2. The server listens on any address (0.0.0.0) on the port 7904
3. Then use curl or any HTTP client
  * To get value from a key : `curl -XGET http://127.0.0.1:7904/foo` 
  * To set value to a key : `curl -XPUT http://127.0.0.1:7904/foo?value=bar`
  * To drop a key : `curl -XDELETE http://127.0.0.1:7904/foo`

