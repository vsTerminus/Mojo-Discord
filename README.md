# Mojo::Discord

This is a set of Perl Modules designed to implement parts of the Discord public API, build on Mojo::IOLoop.


## Moo Branch

This branch is for the migration from Mojo::Base to Moo with the primary goal being to move all Discord state tracking out of the bot client and into the library. Things like user presence, emojis, webhooks, and so on should all be tracked by the library so the client can simply ask for them any time.

At some point I will merge this into Master and it will become Version 2. For now I'm keeping it on a separate branch.

## Modules

The primary modules involved are:

- **Mojo::Discord** - A top level wrapper and single point of entry for all other modules
- **Mojo::Discord::Auth** - OAuth 2 implementation (largely incomplete)
- **Mojo::Discord::REST** - REST API wrapper
- **Mojo::Discord::Gateway** - Discord Websocket client implementation
- **Mojo::Discord::User** - Discord User object, stores properties about users
- **Mojo::Discord::Guild** - Manage all properties related to guilds (Servers)

## Note: This is a spare-time project

I offer no promises as to code completion, timeline, or even support. If you have questions I will try to answer.


## Second Note: Do not rely on this code.

I recommend you do not build anything on this library, as I have a tendency to stop working on this for long stretches at a time... I don't want to be responsible for stalling out your projects. So if you want to build something with this, be prepared to fork the repo and modify it yourself.

## Pre-Requisites

- **Mojo::UserAgent**  and **Mojo::IOLoop** to provide non-blocking asynchronous HTTP calls and websocket functionality.
- **Compress::Zlib**, as some of the incoming messages are compressed Zlib blobs
- **Mojo::JSON** to convert the compressed JSON messages into Perl structures.
- **Mojo::Util** to handle base64 avatar data conversion.
- **JSON::MaybeXS** for proper escaping of unicode characters so discord will encode them correctly.
- **Encode::Guess** to determine whether we're dealing with a compressed stream or not.
- **Data::Dumper** to print any object to screen for debugging.
- **IO::Socket::SSL** is required to fetch the Websocket URL for Discord to connect to.

These dependencies can be installed using cpanminus with the following command in the project root:
    
    cpanm --installdeps .


## Mojo::Discord::Gateway

The Discord "Gateway" is a persistent Websocket connection that sends out events as they happen to all connected clients.
This module monitors the gateway and parses events, although once connected it largely reverts to simply passing the contents of each message to the appropriate callback function, as defined by the user.

The connection process goes a little like this:

1. Request a Gateway URL to connect to
    a. Seems to always return the same URL now, but in the past it looks like they had multiple URLs and servers.
2. Open a websocket connection to the URL received in Step 1.
3. Once connected, send an IDENTIFY message to the server containing info about who we are (Application-wise)
4. Gateway sends us a READY message containing (potentially) a ton of information about our user identity, the servers we are connected to, a heartbeat interval, and so on.
5. Use the Heartbeat Interval supplied in Step 4 to send a HEARTBEAT message to the server periodically. This lets the server know we are still there, and it will close our connection if we do not send it.

Now that we're connected and sending a heartbeat, all we have to do is listen for incoming messages and pass them off to the correct handler and callback functions.

## Mojo::Discord::REST

The REST module exists for when you want your bot to take some kind of action. It's a fairly simple JSON API, you just need to include your bot token in the header for calls.

This module will implement calls for sending messages, indicating the user has started typing, and maybe a few other things that a text chat bot needs to be able to do.

## Mojo::Discord::Auth

This module was created to implement parts of the OAuth2 authentication method for Discord.
It is far from complete and still requires some copy/pasting, but it functions.
Since OAuth is not required for bot clients, this module may not be included in the Mojo::Discord wrapper.
Using it directly might make more sense.

Creating a new Mojo::Discord::Auth object takes the same arguments as above, but also requires an Application ID, Shared Secret, and the Auth Code received from the browser.

The only function implemented so far is request_token, which sends the auth code to the token endpoint and returns 
- Access Token
- Refresh Token
- Expiration Time
- Token Type
- Access Scope

### Example Code:

```perl

#!/usr/bin/env perl

use v5.10;
use warnings;
use strict;

use Mojo::UserAgent;
use Mojo::Discord::Auth;
use Data::Dumper

my $params = {
    'name' => 'Your Application Name',
    'url' => 'https://yourwebsite.com',
    'version' => '0.1',
    'code'  => $ARGV[0],
    'id'    => 'your_application_id',
    'secret' => 'your_application_secret',
};

my $auth = Mojo::Discord::Auth->new($params);

my $token_hash = $auth->request_token();

# Do something with the result
print Dumper($token_hash);
```
