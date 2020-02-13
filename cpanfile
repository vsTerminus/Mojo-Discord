# To use: cpanm --installdeps .
requires 'perl' => '5.010001';              # Minimum required Perl version
requires 'Moo';                             # OO Framework
requires 'strictures', '>=2, <3';           # Enables strict and warnings with specific settings
requires 'namespace::clean';                # Removes declared and imported symbols from your compiled package
requires 'Mojo::UserAgent';                 # HTTP(S) and WebSocket connections
requires 'Mojo::UserAgent::Role::Queued';   # Connection limiting for UserAgent
requires 'Mojo::IOLoop';                    # Event loop required so the program does not exit and can wait for asynchronous operations
requires 'Mojo::JSON';                      # Translate between JSON and Perl hash for talking to Discord
requires 'Mojo::Util';                      # Handles base64 image data conversion
requires 'Mojo::Log';                       # Enables us to log information to disk instead of to screen
requires 'Mojo::Promise';                   # Alternative to callbacks, also used for testing
requires 'JSON::MaybeXS';                   # Provides proper escaping of Unicode characters so discord will encode them correctly
requires 'Compress::Zlib';                  # Handles incoming compressed Zlib blobs
requires 'Encode::Guess';                   # Used to determine if we are dealing with a compressed stream or not
requires 'Data::Dumper';                    # Debugging for complex objects
requires 'IO::Socket::SSL';                 # Used to fetch the WebSocket URL to connect to
requires 'Role::EventEmitter';              # Replaces callbacks, allows client apps to subscribe to events they want to handle
requires 'Time::Duration';                  # Allows us to calculate duration between two times, eg uptime
requires 'URI::Escape';                     # Make any text URL safe


# Unit Tests
requires 'Mojo::Base';                      # Simpler OO framework than Moo, lighter weight
requires 'Test::More';                      # Different ways to "say OK"
requires 'Test::Mockify';                   # Create mock objects for things we don't actually want to call (Eg loggers)
requires 'Test::Mockify::Verify';           # Verify that our mocked objects were actually called
requires 'Test::Mockify::Matcher';          # Define different types of parameters for our mocked objects to accept
requires 'Mock::Quick';                     # Allows us to takeover loaded classes and override their functionality
requires 'Mojolicious::Lite';               # Simple web service we can call instead of Discord's API endpoints
requires 'Mojolicious' => '8.0';            # Require at least version 8 of Mojolicious
