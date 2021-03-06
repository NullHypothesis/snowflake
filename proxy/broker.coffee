###
Communication with the snowflake broker.

Browser snowflakes must register with the broker in order
to get assigned to clients.
###

# Represents a broker running remotely.
class Broker
  @STATUS:
    OK: 200
    GONE: 410
    GATEWAY_TIMEOUT: 504

  @MESSAGE:
    TIMEOUT: 'Timed out waiting for a client offer.'
    UNEXPECTED: 'Unexpected status.'

  clients: 0

  # When interacting with the Broker, snowflake must generate a unique session
  # ID so the Broker can keep track of each proxy's signalling channels.
  # On construction, this Broker object does not do anything until
  # |getClientOffer| is called.
  constructor: (@url) ->
    @clients = 0
    # Ensure url has the right protocol + trailing slash.
    @url = 'http://' + @url if 0 == @url.indexOf('localhost', 0)
    @url = 'https://' + @url if 0 != @url.indexOf('http', 0)
    @url += '/' if '/' != @url.substr -1

  # Promises some client SDP Offer.
  # Registers this Snowflake with the broker using an HTTP POST request, and
  # waits for a response containing some client offer that the Broker chooses
  # for this proxy..
  # TODO: Actually support multiple clients.
  getClientOffer: (id) =>
    new Promise (fulfill, reject) =>
      xhr = new XMLHttpRequest()
      xhr.onreadystatechange = ->
        return if xhr.DONE != xhr.readyState
        switch xhr.status
          when Broker.STATUS.OK
            fulfill xhr.responseText  # Should contain offer.
          when Broker.STATUS.GATEWAY_TIMEOUT
            reject Broker.MESSAGE.TIMEOUT
          else
            log 'Broker ERROR: Unexpected ' + xhr.status +
                ' - ' + xhr.statusText
            snowflake.ui.setStatus ' failure. Please refresh.'
            reject Broker.MESSAGE.UNEXPECTED
      @_xhr = xhr  # Used by spec to fake async Broker interaction
      @_postRequest id, xhr, 'proxy', id

  # Assumes getClientOffer happened, and a WebRTC SDP answer has been generated.
  # Sends it back to the broker, which passes it to back to the original client.
  sendAnswer: (id, answer) ->
    dbg id + ' - Sending answer back to broker...\n'
    dbg answer.sdp
    xhr = new XMLHttpRequest()
    xhr.onreadystatechange = ->
      return if xhr.DONE != xhr.readyState
      switch xhr.status
        when Broker.STATUS.OK
          dbg 'Broker: Successfully replied with answer.'
          dbg xhr.responseText
        when Broker.STATUS.GONE
          dbg 'Broker: No longer valid to reply with answer.'
        else
          dbg 'Broker ERROR: Unexpected ' + xhr.status +
              ' - ' + xhr.statusText
          snowflake.ui.setStatus ' failure. Please refresh.'
    @_postRequest id, xhr, 'answer', JSON.stringify(answer)

  # urlSuffix for the broker is different depending on what action
  # is desired.
  _postRequest: (id, xhr, urlSuffix, payload) =>
    try
      xhr.open 'POST', @url + urlSuffix
      xhr.setRequestHeader('X-Session-ID', id)
    catch err
      ###
      An exception happens here when, for example, NoScript allows the domain
      on which the proxy badge runs, but not the domain to which it's trying
      to make the HTTP xhr. The exception message is like "Component
      returned failure code: 0x805e0006 [nsIXMLHttpRequest.open]" on Firefox.
      ###
      log 'Broker: exception while connecting: ' + err.message
      return
    xhr.send payload
