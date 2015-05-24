# KVS_SERVER

# By Vincent VAN HOLLEBEKE <vincent@compuscene.org>

# a VERY basic key-value store written in nim language

# inspired from the work of Göran Krampe (@GoranKrampe)
# (http://goran.krampe.se/2014/10/25/nim-socketserver/)

# This is my first Nim program.
# So please forgive me if some parts of the code are Bad.
# All critics are welcome !

#  _____                            _
# |_   _|                          | |
#   | |  _ __ ___  _ __   ___  _ __| |_ ___
#   | | | '_ ` _ \| '_ \ / _ \| '__| __/ __|
#  _| |_| | | | | | |_) | (_) | |  | |_\__ \
# |_____|_| |_| |_| .__/ \___/|_|   \__|___/
#                 | |
#                 |_|

import
  threadpool,
  net,
  selectors,
  strutils,
  tables,
  re

#   _____                _              _
#  / ____|              | |            | |
# | |     ___  _ __  ___| |_ __ _ _ __ | |_ ___
# | |    / _ \| '_ \/ __| __/ _` | '_ \| __/ __|
# | |___| (_) | | | \__ \ || (_| | | | | |_\__ \
#  \_____\___/|_| |_|___/\__\__,_|_| |_|\__|___/

const
  SERVER_ADDRESS = "127.0.0.1"
  SERVER_PORT = 7904

#  _______
# |__   __|
#    | |_   _ _ __   ___  ___
#    | | | | | '_ \ / _ \/ __|
#    | | |_| | |_) |  __/\__ \
#    |_|\__, | .__/ \___||___/
#        __/ | |
#       |___/|_|

type
  # State of the HTTP request object
  HTTPRequest_state = enum
    STATE_PARSING, STATE_FINISH, STATE_ERROR

  # State of parsing the HTTP request object
  HTTPRequest_parsestate = enum
    PARSESTATE_COMMAND, PARSESTATE_HEADERS, PARSESTATE_CONTENT

  HTTPRequest_requestline = tuple[`method`: string, url: string, version:string]

  # HTTP request object
  HTTPRequest = ref object of RootObj
    state: HTTPRequest_state
    parsestate: HTTPRequest_parsestate
    requestline: HTTPRequest_requestline
    headers: Table[string, string]
    content: string
    contentlength: int

  # HTTP response object
  HTTPResponse = ref object of RootObj
    code: int
    headers: Table[string, string]
    content: string

  # Command message object
  CommandMsg = ref object of RootObj
    return_channel: ptr ReturnChannel
    command: string
    key: string
    value: string

  # Command channel
  CommandChannel = TChannel[CommandMsg]

  # Return message object
  ReturnMsg = ref object of RootObj
    code: int
    value: string

  # Return channel
  ReturnChannel = TChannel[ReturnMsg]

  # Server object
  Server = ref object of RootObj
    address: string
    port: int
    socket: Socket
    command_channel: ptr CommandChannel

#  _    _ _______ _______ _____  _____                            _
# | |  | |__   __|__   __|  __ \|  __ \                          | |
# | |__| |  | |     | |  | |__) | |__) |___  __ _ _   _  ___  ___| |_
# |  __  |  | |     | |  |  ___/|  _  // _ \/ _` | | | |/ _ \/ __| __|
# | |  | |  | |     | |  | |    | | \ \  __/ (_| | |_| |  __/\__ \ |_
# |_|  |_|  |_|     |_|  |_|    |_|  \_\___|\__, |\__,_|\___||___/\__|
#                                              | |
#                                              |_|

# Constructor
proc newHTTPRequest(): HTTPRequest =
  result = HTTPRequest()
  result.state = STATE_PARSING
  result.parsestate = PARSESTATE_COMMAND
  result.headers = initTable[string,string]()
  result.content = ""

# Parse the HTTP request, line by line
proc receive_request(self: HTTPRequest, buf: string) =
  case self.state

    # If we are still parsing ...
    of STATE_PARSING:
      case self.parsestate

        # We are parsing the first line
        of PARSESTATE_COMMAND:
          # Get the method, url and http protocol version
          var a = buf.split(" ")
          if a.len == 3:
            self.requestline.`method` = a[0]
            self.requestline.url = a[1]
            self.requestline.version = a[2]
            echo("[HTTPREQUEST] received command: method=" & $self.requestline.`method` &  ", url=" & $self.requestline.url & " , version=" & $self.requestline.version)
            self.parsestate = PARSESTATE_HEADERS
          else:
            self.state = STATE_ERROR

        # We are parsing headers
        of PARSESTATE_HEADERS:
          if buf != "\r\n":
            # While there are header lines to parse
            var a: array[0..1,string]
            # Get the header name and value
            if buf.match(re"(.*?):\ (.*)", a):
              # Add the header to the table
              self.headers.add(a[0],a[1])
              echo("[HTTPREQUEST] Received header: [" & a[0] &  "]=[" & a[1] & "]")
            else:
              self.state = STATE_ERROR
          else:
            # If we have parsed all headers
            if self.headers.haskey("Content-Length"):
              # If there is a Content-Length header
              self.contentlength = self.headers["Content-Length"].parseInt()
              self.parsestate = PARSESTATE_CONTENT
              echo("[HTTPREQUEST] We have content")
            else:
              # Else, stop here, no content to parse
              echo("[HTTPREQUEST] We have NO content")
              self.contentlength = 0
              self.state = STATE_FINISH

        # We are parsing content
        of PARSESTATE_CONTENT:
            self.content = self.content & "\r\n" & buf
            if self.content.len >= self.contentlength:
              echo("[HTTPREQUEST] End received content: " & self.content)
              self.state = STATE_FINISH

        # Unknown state
        else:
          discard

    else:
      discard

#  _    _ _______ _______ _____  _____
# | |  | |__   __|__   __|  __ \|  __ \
# | |__| |  | |     | |  | |__) | |__) |___  ___ _ __   ___  _ __  ___  ___
# |  __  |  | |     | |  |  ___/|  _  // _ \/ __| '_ \ / _ \| '_ \/ __|/ _ \
# | |  | |  | |     | |  | |    | | \ \  __/\__ \ |_) | (_) | | | \__ \  __/
# |_|  |_|  |_|     |_|  |_|    |_|  \_\___||___/ .__/ \___/|_| |_|___/\___|
#                                               | |
#                                               |_|

# Constructor
proc newHTTPResponse(): HTTPResponse =
  result = HTTPResponse()
  result.code = -1
  result.headers = initTable[string, string]()
  result.content = ""

# Setter for content
proc setContent(self: HTTPResponse, value: string) =
  self.content = value
  self.headers.add("Content-Length", $value.len)

# Get the message from the status code
proc getMessageCode(self: HTTPResponse): string =
  case self.code
    of 200:
      "OK"
    of 201:
      "Accepted"
    of 204:
      "No Content"
    of 400:
      "Bad Request"
    of 403:
      "Forbidden"
    of 404:
      "Not Found"
    of 405:
      "Method Not Allowed"
    of 500:
      "Internal Server Error"
    else:
      "Unknown Error"

# Return the full response
proc write(self: HTTPResponse): string =
  # The result is composed of the status line,
  result = "HTTP/1.x " & $self.code & " " & self.getMessageCode() & "\r\n"

  # Headers,
  for header in self.headers.pairs():
    result = result & header[0] & ": " & header[1] & "\r\n"

  # And content is present
  if self.content != "":
    result = result & "\r\n" & self.content

#   _____                                          _ __  __
#  / ____|                                        | |  \/  |
# | |     ___  _ __ ___  _ __ ___   __ _ _ __   __| | \  / |___  __ _
# | |    / _ \| '_ ` _ \| '_ ` _ \ / _` | '_ \ / _` | |\/| / __|/ _` |
# | |___| (_) | | | | | | | | | | | (_| | | | | (_| | |  | \__ \ (_| |
#  \_____\___/|_| |_| |_|_| |_| |_|\__,_|_| |_|\__,_|_|  |_|___/\__, |
#                                                                __/ |
#                                                               |___/

# Constructor
proc newCommandMsg(return_channel: ptr ReturnChannel, command: string, key: string, value: string=""): CommandMsg =
  result = CommandMsg()
  result.return_channel = return_channel
  result.command = command
  result.key = key
  result.value = value

#  _____      _                    __  __
# |  __ \    | |                  |  \/  |
# | |__) |___| |_ _   _ _ __ _ __ | \  / |___  __ _
# |  _  // _ \ __| | | | '__| '_ \| |\/| / __|/ _` |
# | | \ \  __/ |_| |_| | |  | | | | |  | \__ \ (_| |
# |_|  \_\___|\__|\__,_|_|  |_| |_|_|  |_|___/\__, |
#                                              __/ |
#                                             |___/

# Constructor
proc newReturnMsg(code: int, value: string=""): ReturnMsg =
  result = ReturnMsg()
  result.code = code
  result.value = value

#  _  __       __      __   _             _____ _                   _   _                        _
# | |/ /       \ \    / /  | |           / ____| |                 | | | |                      | |
# | ' / ___ _   \ \  / /_ _| |_   _  ___| (___ | |_ ___  _ __ ___  | |_| |__  _ __ ___  __ _  __| |
# |  < / _ \ | | \ \/ / _` | | | | |/ _ \\___ \| __/ _ \| '__/ _ \ | __| '_ \| '__/ _ \/ _` |/ _` |
# | . \  __/ |_| |\  / (_| | | |_| |  __/____) | || (_) | | |  __/ | |_| | | | | |  __/ (_| | (_| |
# |_|\_\___|\__, | \/ \__,_|_|\__,_|\___|_____/ \__\___/|_|  \___|  \__|_| |_|_|  \___|\__,_|\__,_|
#            __/ |
#           |___/

proc KeyValueStore(command_channel: ptr CommandChannel) =
  # Initialize the data table
  var data = Table[string, string]()
  data = initTable[string,string]()

  # Put some sample data
  data.add("foo", "bar")

  # Main loop
  while(true):
    # When receive a command message
    var msgrcv = command_channel[].recv()
    echo ("[KEYVALUESTORE] Received command : command=" & msgrcv.command & ", key=" & msgrcv.key & ", value=" & msgrcv.value)

    # Prepare a return message
    var msgsnd: ReturnMsg

    case msgrcv.command:

      # Get command
      of "GET":
        if data.haskey(msgrcv.key):
          msgsnd = newReturnMsg(1, data[msgrcv.key])
        else:
          msgsnd = newReturnMsg(0)

      # Put command
      of "PUT":
        if data.haskey(msgrcv.key):
          data[msgrcv.key] = msgrcv.value
        else:
          data.add(msgrcv.key, msgrcv.value)
        msgsnd = newReturnMsg(1)

      # Del command
      of "DEL":
        if data.haskey(msgrcv.key):
          data.del(msgrcv.key)
          msgsnd = newReturnMsg(1)
        else:
          msgsnd = newReturnMsg(0)

      # Unknown command
      else:
        msgsnd = newReturnMsg(0)

    # Send the return message
    echo("[KEYVALUESTORE] Sent result : code=" & $msgsnd.code & ", value=" & msgsnd.value)
    msgrcv.return_channel[].send(msgsnd)

#   _____
#  / ____|
# | (___   ___ _ ____   _____ _ __
#  \___ \ / _ \ '__\ \ / / _ \ '__|
#  ____) |  __/ |   \ V /  __/ |
# |_____/ \___|_|    \_/ \___|_|

# Constructor
proc newServer(address: string, port: int, command_channel: ptr CommandChannel): Server =
  result = Server()
  result.address = address
  result.port = port
  result.command_channel = command_channel

# Process a client connection
proc ClientHandle(self: Server, socket: Socket) =
  # Initialize a tainted string
  var buf = TaintedString""

  # Initialize a request
  var request: HTTPRequest
  request = newHTTPRequest()

  try:
    # While we are reading the request
    while request.state == STATE_PARSING:
      # Read a new line from the socket
      readLine(socket, buf, timeout = 10000)
      # And send it to the request for parsing
      request.receive_request(buf)

    # Create the response
    var response: HTTPResponse
    response = newHTTPResponse()
    response.code = 400

    # Create a return channel to get messages from the key-value store
    # after sendint commands
    var return_channel: ReturnChannel
    return_channel.open()

    if request.state == STATE_FINISH:
      # Decode the url to find the key and value
      var a: array[0..2,string]
      if request.requestline.url.match(re"^\/([a-zA-Z0-9_]+)(\?value=(.*))?$", a):
        var key = a[0]
        var value = a[2]

        # According to the HTTP method, do different things
        case request.requestline.`method`

          # If method is GET
          of "GET":
            var msgsnd = newCommandMsg(addr(return_channel), "GET", key)
            self.command_channel[].send(msgsnd)
            var msgrcv = return_channel.recv()
            if msgrcv.code == 1:
               response.code = 200
               response.setContent(msgrcv.value)
            else:
              response.code = 404

          # If method is PUT
          of "PUT":
            if value != nil:
              var msgsnd = newCommandMsg(addr(return_channel), "PUT", key, value)
              self.command_channel[].send(msgsnd)
              var msgrcv = return_channel.recv()
              if msgrcv.code == 1:
                response.code = 201

          # If method is DELETE
          of "DELETE":
            var msgsnd = newCommandMsg(addr(return_channel), "DEL", key)
            self.command_channel[].send(msgsnd)
            var msgrcv = return_channel.recv()
            if msgrcv.code == 1:
              response.code = 204
            else:
              response.code = 404

          # Unknown method
          else:
            response.code = 400

    return_channel.close()

    # And sends the response
    socket.send(response.write())

    # That's all !

  except TimeoutError:
      # Handle connection timeout
    echo("[SERVER] Connection timeout")
    socket.close()

  finally:
    # Close properly the connection
    echo("[SERVER] Connection closed")
    socket.close()

# Server loop
proc MainLoop(self: Server) =
  # Create the selector
  var selector = newSelector()
  discard selector.register(self.socket.getFD, {EvRead}, nil)

  while true:

    # If selector has at least one event
    if selector.select(1000).len > 0:

      # Create a client socket
      var client_socket = Socket()

      # Accept the connection
      var address: string
      acceptAddr(self.socket, client_socket, address)
      echo("[SERVER] Received connection from " & address)

      spawn ClientHandle(self, client_socket)

# Make a server listen on an address and a port
proc Listen(self: Server): bool  =
  # Create a new server socket
  self.socket = newSocket()

  try:
    # Bind the address and the port
    self.socket.bindAddr(address = self.address, port = Port(self.port))
    # Then try to listen on it
    self.socket.listen()
    echo("[SERVER] listening on " & self.address & ":" & $self.port)
    # Server loop
    self.MainLoop()

  except OSError:
    # Error handling
    echo("[SERVER] " & getCurrentExceptionMsg())
    return false

  finally:
    # Closes the socket when finished
    self.socket.close()
    return true

#  __  __       _
# |  \/  |     (_)
# | \  / | __ _ _ _ __    _ __  _ __ ___   __ _ _ __ __ _ _ __ ___
# | |\/| |/ _` | | '_ \  | '_ \| '__/ _ \ / _` | '__/ _` | '_ ` _ \
# | |  | | (_| | | | | | | |_) | | | (_) | (_| | | | (_| | | | | | |
# |_|  |_|\__,_|_|_| |_| | .__/|_|  \___/ \__, |_|  \__,_|_| |_| |_|
#                        | |               __/ |
#                        |_|              |___/

when isMainModule:
  # Initialize the command channel
  var command_channel: CommandChannel
  command_channel.open()

  # Start the keyvalue store thread with the command channel
  spawn KeyValueStore(addr(command_channel))

  # Create a new server
  var server = newServer(SERVER_ADDRESS, SERVER_PORT, addr(command_channel))

  # Make the server listen
  discard server.Listen()

  # Close the command channel
  command_channel.close()
