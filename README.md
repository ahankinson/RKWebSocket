RKWebSocket is a Cappuccino implementation of the WebSocket protocol.

## Installation:

RKWebSocket can be installed as a Cappuccino Framework. First, checkout the code from the repo. Then, run `jake all`. This will build the `Debug` and `Release` frameworks and place them in your `$CAPP_BUILD` directory. Then you can symlink this into your project:

```
cd /path/to/project
capp gen -lf -F RKWebSocket .
```

Then you should just be able to import it into your own project:

```
@import <RKWebSocket/RKWebSocket.j>
```


## Example Usage:

```
@implementation MyWebSocketController : CPObject
{
    RKWebSocket     webSocket   @accessors;
}

- (id)init
{
    if (self = [super init])
    {
        webSocket = [RKWebSocket openReconnectingWebSocketWithURL:@"ws://example.org/ws/" delegate:self];
    }

    return self;
}

- (void)socketDidOpen:(RKWebSocket)aSocket
{
    CPLog.debug(@"Web Socket Opened!");
}

- (void)socket:(RKWebSocket)aSocket didCloseWithMessage:(CPString)aMessage
{
    CPLog.debug(@"Web Socket Closed with a Message: " + aMessage);
}

- (void)socket:(RKWebSocket)aSocket didReceiveMessage:(CPString)aMessage
{
    CPLog.debug(@"Web Socket Received a Message: " + aMessage);
    // do stuff with your message
}

- (void)socket:(RKWebSocket)aSocket didReceiveError:(CPError)anError
{
    CPLog.debug(@"Web Socket Received an Error: " + anError);
}

@end
```

Then:

```
var controller = [[MyWebSocketController alloc] init],
    socket = [controller webSocket];

[socket send:@"Hello World!"];  // sends a message to the server
```

If the server sends a message to the client, you should see a message logged to your console (remember to turn on CPLogConsole in your app!).
