{paths} = require '../misc'
messages = require './messages'
client = require './client'

cd = client.import 'cd', false

basic  = require './process/basic'
basic2  = require './process/basic2'
cycler = require './process/cycler'
server = require './process/server'

module.exports =
  server: server

  provider: ->
    switch atom.config.get 'julia-client.juliaOptions.bootMode'
      when 'New Console' then basic2
      when 'Cycler' then cycler
      when 'Basic' then basic

  activate: ->
    paths.getVersion()
      .then =>
        @provider().start? paths.jlpath(), client.clargs()
      .catch ->

  monitorExit: (proc) ->
    proc.onExit (code, signal) ->
      msg = "Julia has stopped"
      if not proc.wrapper and code isnt 0
        msg += ": #{code}"
        if signal then msg += ", #{signal}"
      else
        msg += "."
      client.info msg

  pipeStreams: (proc) ->
    out = (data) -> client.stdout data.toString()
    err = (data) -> client.stderr data.toString()
    proc.flush? out, err
    proc.onStdout out
    proc.onStderr err

  monitor: (proc) ->
    proc.ready = -> false
    @pipeStreams proc
    @monitorExit proc
    client.attach proc
    proc

  monitor2: (proc) ->
    client.emitter.emit('boot', proc.ty)
    proc.ready = -> false
    client.attach(proc)
    return proc

  connect: (proc, sock) ->
    proc.message = (m) -> sock.write JSON.stringify m
    client.readStream sock
    sock.on 'end', -> client.detach()
    sock.on 'error', -> client.detach()
    proc.ready = -> true
    client.flush()
    proc

  start: ->
    [path, args] = [paths.jlpath(), client.clargs()]
    paths.projectDir().then (dir) -> cd dir
    check = paths.getVersion()

    check.catch (err) =>
      messages.jlNotFound paths.jlpath(), err

    proc = check
      .then => @spawnJulia(path, args)
      .then (proc) => if proc.ty? then @monitor2(proc) else @monitor(proc)
    proc
      .then (proc) =>
        Promise.all [proc, proc.socket]
      .then ([proc, sock]) =>
        @connect proc, sock
      .catch (e) ->
        client.detach()
        throw e
    proc

  spawnJulia: (path, args) ->
    @provider().get(path, args)
