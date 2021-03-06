use Base64;
use Cro::HTTP::Middleware;
use Cro::HTTP::Auth;

#| A role to assist with implementing HTTP Basic Authentication middleware.
#| It expects to be parameterized on the type of the session as well as the
#| name of a property on that session object that should hold the username.
#| The consuming class should implement the authenticate method in order to
#| check the username and password, returning True if they are valid. If
#| they are valid, then the auth property of the request will either be set
#| to a new TSession instance with the username property passed to the
#| constructor if it is defined, or just have the username property set
#| otherwise.
role Cro::HTTP::Auth::Basic[::TSession, Str $username-prop] does Cro::HTTP::Middleware::RequestResponse {
    has Str $.realm = 'Login Required';

    method process-requests(Supply $requests --> Supply) {
        supply whenever $requests -> $req {
            with $req.header('Authorization') {
                my $part = $_.split(' ')[1];
                with $part {
                    self!process-auth($req, $_);
                } else {
                    # Authorization header is corrupted.
                    $req.auth = Nil;
                }
            } else {
                # If no credentials are given, no auth is possible by default.
                $req.auth = Nil;
            }
            emit $req;
        }
    }

    method !process-auth($req, $auth) {
        my ($user, $pass) = decode-base64($auth, :bin).decode.split(':');
        if self.authenticate($user, $pass) {
            with $req.auth {
                .^attributes.grep(*.name eq $username-prop)[0].set_value($_, $user);
            } else {
                my %args = $username-prop => $user;
                $req.auth = TSession.new(|%args);
            }
        } else {
            $req.auth = Nil;
        }
    }

    method process-responses(Supply $responses --> Supply) {
        $responses.do: -> Cro::HTTP::Response $response {
            if $response.status == 401 {
                $response.append-header('WWW-Authenticate',
                        'Basic realm="' ~ $!realm ~ '"');
            }
        }
    }

    method authenticate(Str $user, Str $pass --> Bool) { ... }
}
