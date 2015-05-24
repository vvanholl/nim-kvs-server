NIM = nim
OPTIONS = --threads:on --d:release

all: kvs_server

kvs_server: kvs_server.nim
	$(NIM) compile $(OPTIONS) kvs_server.nim

clean: 
	rm -fR nimcache
	rm -fR kvs_server
