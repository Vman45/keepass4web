package KeePass4Web::Apache2;

use Apache2::Const -compile => 'OK';
use Kernel::Keyring;
use KeePass4Web::Constant 'KEYRING_NAME';

sub post_config {
    eval { key_session KEYRING_NAME };

    return Apache2::Const::OK;
}

1;
