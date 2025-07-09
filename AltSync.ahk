/************************************************************************
 * @description A socket library to allow simple communication with alt accounts on the same computer (RDP).
 * @author @Myurius
 * @date 2025/07/09
 * @version 0.1.1
 **********************************************************************
 */

class Sync {
    static _init := 0
    ;Runs to start up sockets
    init() {
        #DllLoad "ws2_32.dll"
        WSAData := Buffer(394 + A_PtrSize)
        if err := DllCall("Ws2_32\WSAStartup", "ushort", 0x0202, "ptr", WSAData.Ptr)
            throw OSError(err)
        
        if NumGet(WSAData, 2, "ushort") != 0x0202
            throw Error("Winsock version 2.2 not available", -1)
        Sync._init := 1         
    }

    static WM_SOCKET := 0x5990
    static FD_READ => 0x01
    static FD_ACCEPT => 0x08
    static FD_CLOSE => 0x20 

    ;Ignored unless AutoSetup is false
    AsyncSelect(Event) {
        if DllCall("ws2_32\WSAAsyncSelect", "ptr", this._sock, "ptr", A_ScriptHwnd, "uint", Sync.WM_SOCKET, "uint", Event)
            throw OSError(DllCall("ws2_32\WSAGetLastError"))
        OnMessage(Sync.WM_SOCKET, this.OnMessage.Bind(this))
    }

    ;Ignored unless AutoSetup is false
    OnMessage(wParam, lParam, msg, hWnd) {
        if msg != Sync.WM_SOCKET
            return
        if lParam & Sync.FD_ACCEPT && this._eventobj.HasMethod("Accept")
            (this._eventobj.Accept)(this)
        if lParam & Sync.FD_CLOSE && this._eventobj.HasMethod("Close")
            (this._eventobj.Close)(this)
        if lParam & Sync.FD_READ && this._eventobj.HasMethod("Receive")
            (this._eventobj.Receive)(this)
    }

    /**
     * Used to close the sockets properly.
     */
    Close() {
        if this is Sync.Alt
            if DllCall("ws2_32\shutdown", "ptr", this._sock, "int", 2) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
        if DllCall("ws2_32\closesocket", "ptr", this._sock) = -1
            throw OSError(DllCall("ws2_32\WSAGetLastError"))
    }

    ;Ignored unless AutoSetup is false
    Createsockaddr(host, port) {
        sockaddr := Buffer(16)
        NumPut("ushort", 2, sockaddr, 0)
        NumPut("ushort", DllCall("ws2_32\htons", "ushort", port), sockaddr, 2)
        NumPut("uint", host, sockaddr, 4)
        return sockaddr
    }

    class Main extends Sync {
        /**
         * Creates a new main account host to control the alts.
         * @param {Object} eventObj Use the Sync.Main.eventObj class or make an object containing an Accept and Close method for handling events.
         * @param {Integer} Alts The number of alts that are allowed to connect. 
         * @param {Integer} AutoSetup Automatically set up the sockets. Don't disable this unless you know how the sockets work.
         * @param {Integer} Port The port which the sockets connect to.
         */
        __New(eventObj, Alts := 3, AutoSetup := 1, Port := 8888) {
            if !Sync._init
                this.init()

            this._eventobj := eventObj
            this._backlog := Alts
            this._sock := -1
            this._host := "0.0.0.0", this._port := Port
            OnExit((*) => (DllCall("ws2_32\WSACleanup")), -1) 

            if AutoSetup {
                this.Bind(this._host, this._port)
                this.Listen()
            }
        }   

        ;Ignored unless AutoSetup is false
        Bind(Host, Port) {            
            if (this._sock := DllCall("ws2_32\socket", "int", 2, "int", 1, "int", 6)) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
            if (h := DllCall("ws2_32\inet_addr", "astr", Host)) = -1
                throw Error("Invalid IP", -1)

            sockaddr := this.Createsockaddr(h, Port)

            if DllCall("ws2_32\bind", "ptr", this._sock, "ptr", sockaddr.Ptr, "int", sockaddr.Size) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
        }

        ;Ignored unless AutoSetup is false
        Listen() {
            if DllCall("ws2_32\listen", "ptr", this._sock, "int", this._backlog) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
            ev := (Sync.FD_ACCEPT | Sync.FD_CLOSE)
            this.AsyncSelect(ev)
        }

        /**
         * Called in the Accept method to accept a new connecting socket.
         * @returns {Integer} Returns a handle to the newly connected socket.
         */
        Accept() {
            if !(sock := DllCall("ws2_32\accept", "ptr", this._sock, "ptr", 0, "ptr", 0))
                if (err := DllCall("ws2_32\WSAGetLastError")) != 10035 ;WSAEWOULDBLOCK
                    throw OSError(err)
            return sock
        }

        class eventObj {
            /**
             * Creates a new event object for the eventObj parameter. 
             * @param Accept The function to call when accepting a connecting socket. Passes a self parameter.
             * @param Close The function to call when the sockets close. Passes a self parameter.
             */
            __New(Accept, Close) {
                this.Accept := {Call: (obj, self) => Accept(self)} 
                this.Close := {Call: (obj, self) => Close(self)}
            }
        }
    }

    class Alt extends Sync {
        /**
         * Creates a new alt account client to communicate with a main account host. 
         * @param {Object} eventObj Use the Sync.Alt.eventObj class or make an object containing a Receive and Close method for handling events.
         * @param {Number} Sock A handle to a socket. When accpeting a new connection put the returned handle here. 
         * @param {Integer} AutoSetup Automatically set up the sockets. Don't disable this unless you know how the sockets work.
         * @param {Integer} Port The port which the sockets connect to.
         */
        __New(eventObj, Sock := -1, AutoSetup := 1, Port := 8888) {
             if !Sync._init
                this.init()

            this._eventobj := eventObj
            this._sock := Sock
            this._host := "127.0.0.1", this._port := Port

            if AutoSetup {
                if this._sock = -1 {
                    this.Connect(this._host, this._port)
                    return
                }
                this.AsyncSelect((Sync.FD_CLOSE | Sync.FD_READ))
            } 
        }

        ;Ignored unless AutoSetup is false
        Connect(Host, Port) {
            if this._sock != -1
                throw Error("Socket already exists", -1)
            
            if (this._sock := DllCall("ws2_32\socket", "int", 2, "int", 1, "int", 6)) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
            if (h := DllCall("ws2_32\inet_addr", "astr", Host)) = -1
                throw Error("Invalid IP", -1)

            sockaddr := this.Createsockaddr(h, port)

            if DllCall("ws2_32\connect", "ptr", this._sock, "ptr", sockaddr.Ptr, "int", sockaddr.Size) = -1
                throw OSError(DllCall("ws2_32\WSAGetLastError"))
            this.AsyncSelect((Sync.FD_CLOSE | Sync.FD_READ))
        }

        /**
         * Receive a string sent from a socket. 
         * @param {String} Encoding The string encoding.
         * @param {Integer} Bytes The buffer size in bytes.
         * @returns {String} Returns the string received from the socket.
         */
        Receive(Encoding := "UTF-8", Bytes := 1024) {
            buf := Buffer(Bytes)
            size := this.ReceiveRaw(buf)
            return StrGet(buf, size, Encoding)
        }

        /**
         * Receive data stored in a buffer. 
         * @param {Buffer} Buf The buffer to store the data in.
         * @returns {Integer} The amount of bytes the data took up. 
         */
        ReceiveRaw(Buf) {
            s := DllCall("ws2_32\recv", "ptr", this._sock, "ptr", Buf.Ptr, "int", Buf.Size, "int", 0)
            if s = -1
                if (err := DllCall("ws2_32\WSAGetLastError")) != 10035 ;WSAEWOULDBLOCK
                    throw OSError(err)
            return s   
        }

        /**
         * Sends a string to a socket.
         * @param {String} Message The string to send. 
         * @param {String} Encoding The encoding the string will be encoded in.
         */
        Send(Message, Encoding := "UTF-8") {
            buf := Buffer(StrPut(Message, Encoding))
            StrPut(Message, buf, Encoding)
            this.SendRaw(buf)
        }

        /**
         * Send a buffer to a socket.
         * @param {Buffer} Buf The buffer to send. 
         */
        SendRaw(Buf) {
            if DllCall("ws2_32\send", "ptr", this._sock, "ptr", buf.Ptr, "int", buf.Size, "int", 0) = -1
                if (err := DllCall("ws2_32\WSAGetLastError")) != 10035 ;WSAEWOULDBLOCK
                    throw OSError(err)
        }

        class eventObj {
            /**
             * Creates a new event object for the eventObj parameter. 
             * @param Receive The function to call when a message is received. Passes a self parameter.
             * @param Close The function to call when the sockets close. Passes a self parameter.
             */
            __New(Receive, Close) {
                this.Receive := {Call: (obj, self) => Receive(self)}
                this.Close := {Call: (obj, self) => Close(self)}
            }
        }
    }
}
