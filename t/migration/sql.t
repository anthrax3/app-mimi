use strict;
use warnings;

use lib 't/lib';

use Test::More;
use Test::Fatal;

use File::Temp qw(tempfile);

use App::mimi::migration::sql;

subtest 'throws when cannot open file' => sub {
    my $migration = _build_migration();

    like exception { $migration->parse('/unlikely-to-exist/42') },
      qr/no such file/i;
};

subtest 'returns simple migration' => sub {
    my $migration = _build_migration();

    my $filename = _write_file(<<'EOF');
SELECT 1
FROM table;
EOF

    my $sql = $migration->parse($filename)->sql;

    is_deeply $sql, ["SELECT 1\nFROM table"];
};

subtest 'skips comments and empty lines' => sub {
    my $migration = _build_migration();

    my $filename = _write_file(<<'EOF');
SELECT 1;
--hello
#there

SELECT 2;
EOF

    my $sql = $migration->parse($filename)->sql;

    is_deeply $sql, ['SELECT 1', 'SELECT 2'];
};

subtest 'parses multiline statements' => sub {
    my $migration = _build_migration();

my $func = <<'EOF';
CREATE OR REPLACE FUNCTION foo()
  RETURNS VOID AS $$
    DECLARE
    BEGIN
      EXECUTE 'DO SMTH'
      USING id;
    END;
  $$ LANGUAGE plpgsql;
EOF

    my $filename = _write_file(<<"EOF");
SELECT 1;

$func

SELECT 2;
EOF

    my $sql = $migration->parse($filename)->sql;

    $func =~ s{;\s+$}{};

    is_deeply $sql, ['SELECT 1', $func, 'SELECT 2'];
};

done_testing;

sub _write_file {
    my ($content) = @_;

    my ($fh, $filename) = tempfile();

    print $fh $content;

    close $fh;

    return $filename;
}

sub _build_migration {
    App::mimi::migration::sql->new;
}
