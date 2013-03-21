Faye = require 'faye'
config = require('config').Danthes
crypto = require('crypto')

module.exports = class Danthes

  @debug: false

  @debugMessage: (message) ->
    console.log(message) if @debug

  # Reset all
  @reset: ->
    @connecting = false
    @fayeClient = null
    @fayeCallbacks = []
    @subscriptions = {}
    @server = "#{config.server}#{config.mount}"
    @disables = []
    @connectionSettings =
      timeout: 120
      retry: 5
      endpoints: {}

  # Connect to faye
  @faye: (callback) =>
    if @fayeClient?
      callback(@fayeClient)
    else
      @fayeCallbacks.push(callback)
      if @server
        @debugMessage 'faye already inited'
        @connectToFaye()

  # Faye extension for incoming and outgoing messages
  @fayeExtension:
    incoming : (message, callback) =>
      @debugMessage "incomming message #{JSON.stringify(message)}"
      callback(message)
    outgoing : (message, callback) =>
      @debugMessage "outgoing message #{JSON.stringify(message)}"
      if message.channel == "/meta/subscribe"
        subscription = @subscriptions[message.subscription]['opts']
        # Attach the signature and timestamp to subscription messages
        message.ext = {} unless message.ext?
        message.ext.danthes_signature = subscription.signature
        message.ext.danthes_timestamp = subscription.timestamp
      else
        message.ext = danthes_token: config.secret_token
      callback(message)

  # Initialize Faye client
  @connectToFaye: ->
    if @server && Faye?
      @debugMessage 'trying to connect faye'
      @fayeClient = new Faye.Client(@server, @connectionSettings)
      @fayeClient.addExtension(@fayeExtension)
      # Disable any features what we want
      @fayeClient.disable(key) for key in @disables
      @debugMessage 'faye connected'
      callback(@fayeClient) for callback in @fayeCallbacks

  # Sign to channel
  # @param [Object] options for signing
  @sign: (options) ->
    @debugMessage 'sign to faye'
    @server = options.server unless @server
    channel = options.channel
    unless @subscriptions[channel]?
      @subscriptions[channel] = {}
      @subscriptions[channel]['callback'] = options['callback'] if options['callback']?
      @subscriptions[channel]['opts'] = @generateSignature channel
      # If we have 'connect' or 'error' option then force channel activation
      if options['connect']? || options['error']?
        @activateChannel channel, options

  # Activating channel subscription
  # @param channel [String] channel name
  # @param options [Object] subscription callback options
  @activateChannel: (channel, options = {}) ->
    return true if @subscriptions[channel]['activated']
    @faye (faye) =>
      subscription = faye.subscribe channel, (message) => @handleResponse(message)
      if subscription?
        @subscriptions[channel]['sub'] = subscription
        subscription.callback =>
          options['connect']?(subscription)
          @debugMessage "subscription for #{channel} is active now"
        subscription.errback (error) =>
          options['error']?(subscription, error)
          @debugMessage "error for #{channel}: #{error.message}"
        @subscriptions[channel]['activated'] = true

  @generateSignature: (channel) ->
    timestamp = Math.round((new Date()).getTime() / 1000)
    signature = crypto.createHash('sha1').update(config.secret_token + channel + timestamp, 'utf8').digest 'hex'
    timestamp: timestamp, signature: signature


  # Handle response from Faye
  # @param [Object] message from Faye
  @handleResponse: (message) ->
    channel = message.channel
    return unless @subscriptions[channel]?
    if callback = @subscriptions[channel]['callback']
      callback(message.data, channel)

  # Disable transports
  # @param [String] name of transport
  @disableTransport: (transport) ->
    return unless transport in ['websocket', 'long-polling', 'callback-polling', 'in-process']
    unless transport in @disables
      @disables.push(transport)
      @debugMessage "#{transport} faye transport will be disabled"
    true

  @publishTo: (channel, data) ->
    @faye (faye) -> faye.publish channel, channel: channel, data: data

  # Subscribe to channel with callback
  # @param channel [String] Channel name
  # @param callback [Function] Callback function
  # @param options [Object] subscription callbacks options
  @subscribe: (channel, callback, options = {}) ->
    @debugMessage "subscribing to #{channel}"
    if @subscriptions[channel]?
      @activateChannel(channel, options)
      # Changing callback on every call
      @subscriptions[channel]['callback'] = callback
    else
      @debugMessage "Cannot subscribe on channel '#{channel}'. You need sign to channel first."
      return false
    true

  # Unsubscribe from channel
  # @param [String] Channel name
  # @param [Boolean] Full unsubscribe
  @unsubscribe: (channel, fullUnsubscribe = false) ->
    @debugMessage "unsubscribing from #{channel}"
    if @subscriptions[channel] && @subscriptions[channel]['activated']
      @subscriptions[channel]['sub'].cancel()
      if fullUnsubscribe
        delete @subscriptions[channel]
      else
        delete @subscriptions[channel]['activated']
        delete @subscriptions[channel]['sub']

  # Unsubscribe from all channels
  @unsubscribeAll: ->
    @unsubscribe(channel) for channel, _ of @subscriptions

Danthes.reset()