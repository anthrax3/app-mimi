package App::mimi::db;

use strict;
use warnings;

use Carp qw(croak);

sub new {
    my $class = shift;
    my (%params) = @_;

    my $self = {};
    bless $self, $class;

    $self->{dbh} = $params{dbh} or croak 'dbh required';

    $self->{columns} = [qw/no created status error/];

    return $self;
}

sub is_prepared {
    my $self = shift;

    local $SIG{__WARN__} = sub { };

    my $rv;
    eval { $rv = $self->{dbh}->do('SELECT 1 FROM mimi LIMIT 1') };

    return unless $rv;

    return 1;
}

sub prepare {
    my $self = shift;

    $self->{dbh}->do(<<'EOF');
    CREATE TABLE mimi (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        created INTEGER NOT NULL,
        no INTEGER NOT NULL,
        status VARCHAR(32) NOT NULL,
        error VARCHAR(255)
    );
EOF
}

sub fix_last_migration {
    my $self = shift;

    my $last_migration = $self->fetch_last_migration;
    return unless $last_migration;

    $self->{dbh}->do("UPDATE mimi SET status = 'success' WHERE id=$last_migration->{id}") or die $!;

    return $self;
}

sub create_migration {
    my $self = shift;
    my (%migration) = @_;

    $migration{created} ||= time;

    my $columns = join ',', keys %migration;
    my $values = join ',', map { "'$_'" } values %migration;

    $self->{dbh}->do("INSERT INTO mimi ($columns) VALUES ($values)") or die $!;

    return $self;
}

sub fetch_last_migration {
    my $self = shift;

    my $sth =
      $self->{dbh}->prepare(
        'SELECT id, no, created, status, error FROM mimi ORDER BY id DESC LIMIT 1');
    my $rv = $sth->execute or die $!;

    my $row = $sth->fetchall_arrayref->[0];
    return unless $row;

    my $migration = {};
    for (qw/id no created status error/) {
        $migration->{$_} = shift @$row;
    }

    return $migration;
}

1;
