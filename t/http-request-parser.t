use Crow::HTTP::RequestParser;
use Crow::HTTP::Request;
use Crow::TCP;
use Test;

ok Crow::HTTP::RequestParser ~~ Crow::Processor,
    'HTTP request parser is a processor';
ok Crow::HTTP::RequestParser.consumes === Crow::TCP::Message,
    'HTTP request parser consumes TCP messages';
ok Crow::HTTP::RequestParser.produces === Crow::HTTP::Request,
    'HTTP request parser produces HTTP requests';

sub test-request-to-tcp-message($req) {
    # We replace \n with \r\n in the request headers here, so the tests can
    # look pretty.
    my ($headers, $body) = $req.split("\n\n");
    $headers .= subst("\n", "\r\n", :g);
    my $data = "$headers\r\n\r\n$body".encode('latin-1');
    return Crow::TCP::Message.new(:$data);
}

sub parses($desc, $test-request, *@checks, *%config) {
    my $testee = Crow::HTTP::RequestParser.new(|%config);
    my $fake-in = Supplier.new;
    $testee.processor($fake-in.Supply).tap:
        -> $request {
            pass $desc;
            for @checks.kv -> $i, $check {
                ok $check($request), "check {$i + 1 }";
            }
            return;
        },
        quit => {
            diag "Request parsing failed: $_";
            flunk $desc;
            skip 'Failed to parse', @checks.elems;
            return;
        };
    $fake-in.emit(test-request-to-tcp-message($test-request));

    # We only reach here if we fail emit a HTTP message (see `return`s above).
    diag 'Request parser failed to emit a HTTP request';
    flunk $desc;
    skip 'Did not get request', @checks.elems;
}

sub refuses($desc, $test-request, *@checks, *%config) {
    my $testee = Crow::HTTP::RequestParser.new(|%config);
    my $fake-in = Supplier.new;
    $testee.processor($fake-in.Supply).tap:
        -> $request {
            diag "Request parsing unexpectedly succeeded";
            flunk $desc;
            skip 'Incorrectly parsed header', @checks.elems;
            return;
        },
        quit => -> $exception {
            pass $desc;
            for @checks.kv -> $i, $check {
                ok $check($exception), "check {$i + 1}";
            }
            return;
        };
    $fake-in.emit(test-request-to-tcp-message($test-request));

    # We only reach here if we fail emit a HTTP message (see `return`s above).
    diag 'Request parser failed to emit a HTTP request';
    flunk $desc;
    skip 'Did not get request', @checks.elems;
}

refuses 'Malformed request line - only verb', q:to/REQUEST/,
    GET

    REQUEST
    *.status == 400;

refuses 'Malformed request line - no version', q:to/REQUEST/,
    GET /

    REQUEST
    *.status == 400;

refuses 'Malformed request line - utter crap', q:to/REQUEST/,
    lol I don't even know know how to http

    REQUEST
    *.status == 400;

refuses 'Malformed HTTP version (1)', q:to/REQUEST/,
    GET / omg!!

    REQUEST
    *.status == 400;

refuses 'Malformed HTTP version (2)', q:to/REQUEST/,
    GET / FTP/1.1

    REQUEST
    *.status == 400;

refuses 'Malformed HTTP version (3)', q:to/REQUEST/,
    GET / HTTP/1

    REQUEST
    *.status == 400;

refuses 'Malformed HTTP version (4)', q:to/REQUEST/,
    GET / HTTP/10.1

    REQUEST
    *.status == 400;

refuses 'Malformed HTTP version (5)', q:to/REQUEST/,
    GET / HTTP/1.10

    REQUEST
    *.status == 400;

refuses 'Unimplemented HTTP version', q:to/REQUEST/,
    GET / HTTP/2.0

    REQUEST
    *.status == 501;

parses 'Simple GET request with no headers', q:to/REQUEST/,
    GET / HTTP/1.1

    REQUEST
    *.method eq 'GET',
    *.target eq '/',
    *.http-version eq '1.1';

parses 'Simple HEAD request with no headers', q:to/REQUEST/,
    HEAD / HTTP/1.1

    REQUEST
    *.method eq 'HEAD',
    *.target eq '/',
    *.http-version eq '1.1';

parses 'Simple POST request with no headers', q:to/REQUEST/,
    POST / HTTP/1.1

    REQUEST
    *.method eq 'POST',
    *.target eq '/',
    *.http-version eq '1.1';

parses 'Simple PUT request with no headers', q:to/REQUEST/,
    PUT / HTTP/1.1

    REQUEST
    *.method eq 'PUT',
    *.target eq '/',
    *.http-version eq '1.1';

parses 'Simple DELETE request with no headers', q:to/REQUEST/,
    DELETE / HTTP/1.1

    REQUEST
    *.method eq 'DELETE',
    *.target eq '/',
    *.http-version eq '1.1';

parses 'Simple OPTIONS request with no headers', q:to/REQUEST/,
    OPTIONS / HTTP/1.1

    REQUEST
    *.method eq 'OPTIONS',
    *.target eq '/',
    *.http-version eq '1.1';

refuses 'The TRACE method, as it is not implemented by default', q:to/REQUEST/,
    TRACE / HTTP/1.1

    REQUEST
    *.status == 501;

refuses 'The PATCH method, as it is not implemented by default', q:to/REQUEST/,
    PATCH / HTTP/1.1

    REQUEST
    *.status == 501;

parses 'The PATCH method if included in allowed-methods',
    allowed-methods => <GET PUT POST DELETE PATCH>,
    q:to/REQUEST/,
    PATCH / HTTP/1.1

    REQUEST
    *.method eq 'PATCH',
    *.target eq '/',
    *.http-version eq '1.1';

refuses 'PUT when it is not included in the allowed methods',
    allowed-methods => <GET HEAD OPTIONS>,
    q:to/REQUEST/,
    PUT / HTTP/1.1

    REQUEST
    *.status == 501;

done-testing;
