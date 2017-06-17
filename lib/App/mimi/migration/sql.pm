package App::mimi::migration::sql;

use strict;
use warnings;

use Carp qw(croak);

sub new {
    my $class = shift;

    my $self = {};
    bless $self, $class;

    return $self;
}

sub sql { shift->{sql} }

sub parse {
    my $self = shift;
    my ($file) = @_;

    my @lines = map { chomp; $_ } $self->_slurp($file);
    my $multiline = '';

    my @sql;
    my @parts;
    foreach my $line (@lines) {
        next if $line =~ m/^(?:--|#)/;

        push @parts, $line;

        pos $parts[-1] = 0;

        if ($multiline) {
            if ($parts[-1] =~ m/\G.*?\Q$multiline\E/gc) {
                $multiline = '';
            }
            else {
                next;
            }
        }

        if ($parts[-1] =~ m/\G.*?(\$.*?\$)/gc) {
            $multiline = $1;
        }

        if (!$multiline && $parts[-1] =~ s/;$//) {
            push @sql, $self->_join(@parts);
            @parts = ();
        }
    }

    push @sql, $self->_join(@parts) if @parts;

    @sql = grep { length } map { s/^\s+//; s/\s+$//; $_ } @sql;

    $self->{sql} = \@sql;

    return $self;
}

sub execute {
    my $self = shift;
    my ($dbh) = @_;

    my $e;
    my $last_query = '';

    my $sqls = $self->{sql};

    eval {
        for my $sql (@{$sqls || []}) {
            $last_query = $sql;

            $dbh->do($sql);
        }

        1;
    } or do {
        $e = $@;

        $e =~ s{ at .*? line \d+.$}{};
    };

    return { success => defined($e) ? 0 : 1, error => $e };
}

sub _join {
    my $self = shift;
    my (@parts) = @_;

    return join "\n", @parts;
}

sub _slurp {
    my $self = shift;
    my ($file) = @_;

    open my $fh, '<', $file or croak "Can't open file '$file': $!";
    <$fh>;
}

1;
