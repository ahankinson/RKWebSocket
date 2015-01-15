/*
 * RKWebSocket.j
 * RKWebSocket
 *
 * Created by Andrew Hankinson on January 7, 2015.
 *
 * Copyright 2015. All rights reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */
@import <Foundation/CPObject.j>
@import <Foundation/CPTimer.j>

@typedef WebSocket

var RKWebSocketConnectingState = 0,
    RKWebSocketOpenState       = 1,
    RKWebSocketClosingState    = 2,
    RKWebSocketClosedState     = 3;

var RKWebSocketDelegate_socketDidOpen              = 1 << 0,
    RKWebSocketDelegate_socket_didReceiveMessage   = 1 << 1,
    RKWebSocketDelegate_socket_didCloseWithMessage = 1 << 2,
    RKWebSocketDelegate_socket_didReceiveError     = 1 << 3;

@protocol RKWebSocketDelegate <CPObject>

@optional
 - (void)socketDidOpen:(RKWebSocket)aSocket;
 - (void)socket:(RKWebSocket)aSocket didCloseWithMessage:(CPString)aMessage;
 - (void)socket:(RKWebSocket)aSocket didReceiveMessage:(CPString)aMessage;
 - (void)socket:(RKWebSocket)aSocket didReceiveError:(CPError)anError;

@end


/*
 * This is an implementation of the JS WebSocket functionality.
 * This will periodically send out a heartbeat to ensure the connection
 * stays open.
 * 
 */
@implementation RKWebSocket : CPObject
{
    WebSocket                   _ws;
    CPString                    _socketUrl;
    id <RKWebSocketDelegate>    _delegate;
    CPInteger                   _implementedDelegateMethods;
    CPTimer                     _heartbeatTimer;
    CPInteger                   _missedHeartbeats;
    CPInteger                   _heartbeatAttempts;
    CPString                    _heartbeatMessage;
    BOOL                        _shouldReconnect;
    CPInteger                   _missedReconnects;
    CPInteger                   _reconnectAttempts;
    CPInteger                   _reconnectInterval;
    CPTimer                     _reconnectTimer;
    BOOL                        _isReconnecting;
}

/*
 * Opens a web socket at a given URL and assigns a delegate class for any callbacks.
 *  If the web socket gets disconnected, sockets initialized with this method will not
 *  attempt to reconnect. Use `openReconnectingWebSocketWithURL:delegate` if you want
 *  one that will attempt to reconnect.
 *  @param aURL A URL of a Web Socket Server
 *  @param aDelegate A delegate class for the Web Socket communication
 **/
+ (id)openWebSocketWithURL:(CPString)aUrl delegate:(id)aDelegate
{
    return [[self alloc] initWithURL:aUrl
                            delegate:aDelegate
                           reconnect:NO];
}

/*
 * Opens a web socket at a given URL and assigns a delegate class for any callbacks.
 *  If the web socket gets disconnected, sockets initialized with this method will
 *  attempt to reconnect. Use `openWebSocketWithURL:delegate` if you do not want
 *  one that will attempt to reconnect.
 *  @param aURL A URL of a Web Socket Server
 *  @param aDelegate A delegate class for the Web Socket communication
 **/
+ (id)openReconnectingWebSocketWithURL:(CPString)aUrl delegate:(id)aDelegate
{
    return [[self alloc] initWithURL:aUrl
                            delegate:aDelegate
                           reconnect:YES];
}

/*
 * Initializes an RKWebSocket instance. 
 *  @param aURL A URL of a Web Socket Server
 *  @param aDelegate A delegate class for the Web Socket communication
 *  @param shouldReconnect A Boolean value to determine if the Web Socket should try to reconnect.
 **/
- (id)initWithURL:(CPString)aUrl delegate:(id)aDelegate reconnect:(BOOL)shouldReconnect
{
    if (self = [super init])
    {
        CPLogRegister(CPLogConsole, "debug");
        CPLog.debug(@"Initializing RKWebSocket");

        _socketUrl = aUrl;
        _shouldReconnect = shouldReconnect;
        _reconnectInterval = 5; // try to reconnect every five seconds
        _missedReconnects = 0;
        _reconnectAttempts = 6;  // make six attempts to reconnect before giving up.
        _isReconnecting = NO;
        _heartbeatMessage = '--heartbeat--';  // it's a love beat!
        _heartbeatAttempts = 3;  // make three attempts before giving up.
        _ws = new WebSocket(_socketUrl);

        [self setDelegate:aDelegate];

        /*
            Set up the WebSocket callbacks and forward them on to the delegate.
         */
        _ws.onopen = function()
        {
            CPLog.debug(@"Web Socket Connection Opened");
            _missedHeartbeats = 0;

            if (RKWebSocketDelegate_socketDidOpen & _implementedDelegateMethods)
                [_delegate socketDidOpen:self];

            // if it was reconnecting, we're now connected again so reset everything;
            if (_isReconnecting)
            {
                CPLog.debug(@"Successfully reconnected.");

                _missedReconnects = 0;
                _isReconnecting = NO;
                [_reconnectTimer invalidate];
                _reconnectTimer = nil;
            }
        }

        _ws.onclose = function(event)
        {
            CPLog.debug(@"Web Socket Connection Closed");
            [_heartbeatTimer invalidate];

            if (RKWebSocketDelegate_socket_didCloseWithMessage & _implementedDelegateMethods)
                [_delegate socket:self didCloseWithMessage:event.data];

            if (_shouldReconnect)
            {
                CPLog.debug("Closed. Attempting to reconnect...");

                var _reconnectCallback = function ()
                {
                    try
                    {
                        _ws = new WebSocket(_socketUrl);
                    }
                    catch (error)
                    {
                        CPLog.debug(@"Caught error in trying to reconnect.");

                        _missedReconnects++;
                        if (_missedReconnects > _reconnectAttempts)
                        {
                            _isReconnecting = NO;
                            _missedReconnects = 0;
                            [_reconnectTimer invalidate];
                            _reconnectTimer = nil;

                            throw new Error("Too many reconnect attempts. Giving up.");
                        }
                    }
                };

                _isReconnecting = YES;
                _reconnectTimer = [CPTimer scheduledTimerWithTimeInterval:_reconnectInterval
                                                                 callback:_reconnectCallback
                                                                  repeats:YES];
            }

        };

        _ws.onmessage = function(event)
        {
            // we don't need to alert the delegate if the message is simply a heartbeat.
            if (event.data === _heartbeatMessage)
            {
                CPLog.debug(@"Web Socket Connection Received Heartbeat");
                _missedHeartbeats = 0;
                return;
            }

            CPLog.debug(@"Web Socket Connection Received Message");
            if (RKWebSocketDelegate_socket_didReceiveMessage & _implementedDelegateMethods)
                [_delegate socket:self didReceiveMessage:event.data];
        }

        _ws.onerror = function(event)
        {
            CPLog.debug(@"Web Socket Connection Received Error");
            // TODO: Convert event.data to a CPError

            if (RKWebSocketDelegate_socket_didReceiveError & _implementedDelegateMethods)
                [_delegate socket:self didReceiveError:event.data];
        }

        /*
         *  Set up the heartbeat timer.
         */
        var heartbeatTimerCallback = function ()
        {
            try
            {
                // _missedHeartbeats gets reset each time the message is received.
                _missedHeartbeats++;
                if (_missedHeartbeats > _heartbeatAttempts)
                {
                    [_heartbeatTimer invalidate];
                    _missedHeartbeats = 0;
                    throw new Error('Too Many Missed Heartbeats. Giving up.');
                }
            }
            catch (error)
            {
                [_heartbeatTimer invalidate];
                CPLog.error("Closing connection. Reason: " + error.message);
                // this should also fire the delegate method for closing.
                _ws.close();
            }
        };

        _heartbeatTimer = [CPTimer scheduledTimerWithTimeInterval:4
                                                         callback:heartbeatTimerCallback
                                                          repeats:YES];
    }

    return self;
}

/*
 *  Delegates for RKWebSocket should conform to the RKWebSocketDelegate protocol.
 *  @param aDelegate the delegate object for the Web Socket.
 **/
- (void)setDelegate:(id <RKWebSocketDelegate>)aDelegate
{
    if (_delegate === aDelegate)
        return;

    _delegate = aDelegate;
    _implementedDelegateMethods = 0;

    if ([_delegate respondsToSelector:@selector(socketDidOpen:)])
        _implementedDelegateMethods |= RKWebSocketDelegate_socketDidOpen;

    if ([_delegate respondsToSelector:@selector(socket:didCloseWithMessage:)])
        _implementedDelegateMethods |= RKWebSocketDelegate_socket_didCloseWithMessage;

    if ([_delegate respondsToSelector:@selector(socket:didReceiveMessage:)])
        _implementedDelegateMethods |= RKWebSocketDelegate_socket_didReceiveMessage;

    if ([_delegate respondsToSelector:@selector(socket:didReceiveError:)])
        _implementedDelegateMethods |= RKWebSocketDelegate_socket_didReceiveError;
}

/*
 *  Returns the URL of the connection to the Web Socket server
 **/
- (CPString)URL
{
    return _ws.url;
}

/*
 * Returns the ready state (i.e., status) of the Web Socket connection. These states correspond to the following
 * constants:
 *  RKWebSocketConnectingState = 0,
 *  RKWebSocketOpenState       = 1,
 *  RKWebSocketClosingState    = 2,
 *  RKWebSocketClosedState     = 3;
 **/
- (int)readyState
{
    return _ws.readyState;
}

/*
 * Closes the web socket connection.
 **/
- (void)close
{
    _ws.close();
}

/*
 * Closes the web socket with a code and a human-readable reason.
 * @param aCode A numerical code indicating the reason why it was closed.
 * @param aReason A human-readable message giving the reason for closure.
 **/
- (void)closeWithCode:(CPNumber)aCode reason:(CPString)aReason
{
    _ws.close(aCode, aReason);
}

/*
 * Sends a message to the web socket. It will first check to see if the Web Socket is in a state to accept messages.
 * @param data Data objects to send to the Web Socket Server
 * @return BOOL YES if the message send was successful; otherwise NO.
 *
 **/
- (BOOL)send:(JSObject)data
{
    if ([self readyState] !== RKWebSocketConnectingState ||
        [self readyState] !== RKWebSocketClosedState ||
        [self readyState] !== RKWebSocketClosingState)
        return _ws.send(data);
    else
        return NO;
}

@end
