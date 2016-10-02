package KeePass4Web;
use strict;
use warnings;

use Dancer ':syntax';
use Dancer::Plugin::Ajax;
use MIME::Base64;

BEGIN {
    # change to correct dir if using mod_perl2
    if ($ENV{MOD_PERL} || $ENV{MOD_PERL_API_VERSION}) {
        chdir config->{appdir};
    }
}

use KeePass4Web::KeePass;
use KeePass4Web::Backend;
use KeePass4Web::Auth;
use KeePass4Web::Constant;


hook 'before' => sub {
    # TODO: check here for 'authenticated', to allow empty user authentication (auth_backend = '')

    # check session
    if (!session SESSION_USERNAME and request->path_info !~ /^\/$|^\/user_login$|^\/authenticated$/) {
        status UNAUTHORIZED;
        request->path_info('/');
    }
    else {
       # TODO: check CSRF token;
    }
};

ajax '/user_login' => sub {
    return failure 'No user authentication configured', MTHD_NOT_ALLOWED if !config->{auth_backend};
    return failure 'Already logged in', MTHD_NOT_ALLOWED if session SESSION_USERNAME;

    my $username = param 'username';
    my $password = param 'password';

    if (!defined $username or !defined $password) {
        return failure 'Username or password not supplied', UNAUTHORIZED;
    }

    info 'User login attempt: ', $username;

    # may return more info of user as HoA
    my $userinfo = eval {
        KeePass4Web::Auth::auth($username, $password);
    };
    if ($@) {
        debug "$username: $@";
        # passing standard error message, won't give any clues to attackers
        return failure 'User authentication failed', UNAUTHORIZED;
    }

    debug 'User info: ', $userinfo;

    if (config->{auth_reuse_cred}) {
        eval {
            KeePass4Web::Backend::credentials_init(scalar params);
        };
        if ($@) {
            debug "$username: $@";
            # warn only and give user chance to enter deviating credentials
            warning "User $username: Backend credentials reuse configured, but backend authentication failed";
        }
    }

    info 'User login successful: ', $username;
    session SESSION_USERNAME, $username;

    # set a CN to display on the web interface
    my $cn = ref $userinfo eq 'HASH' && $userinfo->{CN} ? $userinfo->{CN}->[0] : lc $username;
    $cn //= lc $username;

    session SESSION_CN, $cn;

    return success 'Login successful';
};


ajax '/backend_login' => sub {
    return failure 'Already logged into backend', MTHD_NOT_ALLOWED if eval { KeePass4Web::Backend::authenticated };

    my $params = params;

    unless (ref $params eq 'HASH' && %$params) {
        return failure 'No parameters supplied', UNAUTHORIZED;
    }


    # param check happens downstream
    eval {
        KeePass4Web::Backend::credentials_init($params)
    };
    if ($@) {
        debug session(SESSION_USERNAME), ": $@";
        # using error message of backend, in case something like decryption of a repository fails
        # and we need to distinguish (and give a hint to the user)
        return failure $@, UNAUTHORIZED;
    }


    return success 'Login successful';
};


ajax '/db_login' => sub {
    return failure 'DB already open', MTHD_NOT_ALLOWED if eval { KeePass4Web::KeePass::opened };

    my $password = param 'password';
    # grabbing the hidden base64 encoded input field
    my $keyfile  = param 'key';


    if (!$password and !$keyfile) {
        return failure 'Neither password nor keyfile supplied';
    }

    info session(SESSION_USERNAME), ': DB decryption attempt';

	if ($keyfile) {
        # cut html file api prefix and decode from base64
		$keyfile = eval { decode_base64 param('key') =~ s/^.*?,//r };
		if ($@) {
			info session(SESSION_USERNAME), ": $@";
			return failure 'Failed to parse key file';
		}
	}

    eval {
        KeePass4Web::KeePass::fetch_and_decrypt(password => $password, keyfile => \$keyfile);
    };
    if ($@) {
        info session(SESSION_USERNAME), ": $@";
        return failure 'DB decryption failed', UNAUTHORIZED;
    }

    info session(SESSION_USERNAME), ': DB decryption successful';

    return success 'Login successful';
};


ajax '/logout' => sub {
    eval { KeePass4Web::KeePass::clear_db };
    return failure 'Not logged in', MTHD_NOT_ALLOWED if !session->destroy;
    return success 'Logged out';
};

ajax '/authenticated' => sub {
    my %auth = (
        user    => 0+!config->{auth_backend},
        backend => 0,
        db      => 0,
    );

    # shortcut, if auth backend is configured and user auth is false
    # setting $auth{user} to reuse it further below
    if (config->{auth_backend} and not $auth{user} = 0+!!session SESSION_USERNAME) {
        return failure \%auth, UNAUTHORIZED;
    }

    $auth{backend} = 1 if eval { KeePass4Web::Backend::authenticated };
    $auth{db}      = 1 if eval { KeePass4Web::KeePass::opened };


    $auth{data} = {
        cn              => session(SESSION_CN),
        credentials_tpl => KeePass4Web::Backend::credentials_tpl(),
    };

    # return auth fail if any auth is false
    foreach my $val (values %auth) {
        return failure \%auth, UNAUTHORIZED if !$val;
    }

    return success 'Authenticated';
};

any ['post', 'get'] => '/' => sub {
    # TODO: insert csrf token
    send_file 'index.html';
};


1;