use strict;
use warnings;

use lib 't/lib';

use Test::More;
use Test::Fatal;
use Test::Deep;
use Test::TempDir::Tiny;

use File::Temp qw(tempfile);

use App::mimi::migration::perl;

subtest 'throws when cannot open file' => sub {
    my $migration = _build_migration();

    like exception { $migration->parse('/unlikely-to-exist/42') },
      qr/no such file/i;
};

subtest 'runs perl code' => sub {
    my $migration = _build_migration();

    my $filename = _write_file(<<"EOF");
package Migration::01;
sub migrate {
    die 'error';
}
1;
EOF

    $migration->parse($filename);

    my $result = $migration->execute();

    cmp_deeply $result, { success => 0, error => re(qr/error/) };
};

subtest 'runs perl code deeply nested' => sub {
    my $migration = _build_migration();

    my $tempdir = tempdir();
    mkdir "$tempdir/schema";

    my $filename = _write_file(<<"EOF", "$tempdir/schema/02-foo-bar.pm");
package Migration::02;
sub migrate {
    \$ENV{MIGRATED}++;
}
1;
EOF

    $migration->parse($filename);

    my $result = $migration->execute();

    ok $ENV{MIGRATED};

    cmp_deeply $result, { success => 1, error => undef };
};

subtest 'returns error' => sub {
    my $migration = _build_migration();

    my $filename = _write_file(<<"EOF");
package Migration::01;
sub migrate {
    \$ENV{MIGRATED}++;
}
1;
EOF

    $migration->parse($filename);

    my $result = $migration->execute();

    ok $ENV{MIGRATED};

    is_deeply $result, { success => 1, error => undef };
};

done_testing;

sub _write_file {
    my ($content, $path) = @_;

    my ($fh, $filename);

    if ($path) {
        open $fh, '>', $path or die $!;
        $filename = $path;
    }
    else {
        ( $fh, $filename ) = tempfile();
    }

    print $fh $content;

    close $fh;

    return $filename;
}

sub _build_migration {
    App::mimi::migration::perl->new;
}
