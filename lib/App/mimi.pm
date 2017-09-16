package App::mimi;

use strict;
use warnings;

our $VERSION = '0.03';

use Carp qw(croak);
use Cwd qw(abs_path);
use File::Spec;
use File::Basename ();
use DBI;
use App::mimi::db;
use App::mimi::migration;

sub new {
    my $class = shift;
    my (%params) = @_;

    my $self = {};
    bless $self, $class;

    $self->{dsn}               = $params{dsn};
    $self->{table}             = $params{table} // 'mimi';
    $self->{schema}            = $params{schema};
    $self->{initial_schema}    = $params{initial_schema};
    $self->{initial_migration} = $params{initial_migration};
    $self->{dry_run}           = $params{dry_run};
    $self->{verbose}           = $params{verbose};
    $self->{migration}         = $params{migration};
    $self->{setup}             = $params{setup};
    $self->{dbh}               = $params{dbh};

    return $self;
}

sub setup {
    my $self = shift;

    my $db = $self->_build_db;

    if ($db->is_prepared) {
        $self->_print("Notice: migrations table already exists");
        return;
    }

    $self->_print("Creating migrations table");

    $db->prepare unless $self->_is_dry_run;

    if (my $initial_schema = $self->{initial_schema}) {
        my $migration = App::mimi::migration->build('sql')->parse($initial_schema);

        my $initial_migration = $self->_detect_initial_migration($self->{initial_migration} || 0);

        $self->_print("Initializing with '$initial_schema' ($initial_migration)");

        next if $self->_is_dry_run;

        my $dbh = $self->{dbh};

        my $result = $migration->execute($dbh);
        die "Error: $result->{error}\n" unless $result->{success};
    }
    elsif ($self->{initial_migration}) {
        my $initial_migration = $self->_detect_initial_migration($self->{initial_migration} || 0);

        $self->_print("Setting initial migration ($initial_migration)");

        $db->create_migration(
            no      => $initial_migration,
            created => time,
            status  => 'success'
        ) unless $self->_is_dry_run;
    }

    return $self;
}

sub migrate {
    my $self = shift;

    die "Error: Schema directory is required\n"
      unless $self->{schema} && -d $self->{schema};

    if ($self->{setup}) {
        $self->setup;
    }

    my @schema_files = grep { !/^\./ } glob("$self->{schema}/*");
    die "Error: No schema files found in '$self->{schema}'\n"
      unless @schema_files;

    my $db = $self->_build_db_prepared;

    my $last_migration = $db->fetch_last_migration;

    if ($last_migration && $last_migration->{status} ne 'success') {
        $last_migration->{error} ||= 'Unknown error';
        die "Error: Migrations are dirty. "
          . "Last error was in migration $last_migration->{no}:\n\n"
          . "    $last_migration->{error}\n"
          . "After fixing the problem run <fix> command\n";
    }

    $self->_print("Found last migration $last_migration->{no}")
      if $last_migration;

    my @migrations;
    for my $file (@schema_files) {
        my ($no, $name) = File::Basename::basename($file) =~ /^(\d+)(.*)$/;
        next unless $no && $name;

        my ($ext) = $name =~ m/\.([^\.]+)$/;
        next unless $ext;

        $no = int($no);

        next if $last_migration && $no <= $last_migration->{no};

        eval {
            my $migration = App::mimi::migration->build($ext)->parse(abs_path($file));

            push @migrations,
              {
                file      => $file,
                no        => $no,
                name      => $name,
                migration => $migration
              };

            1;
        } or do {
            my $e = $@;

            $self->_finalize($no, {success => 0, error => $e});
        };
    }

    if (@migrations) {
        foreach my $migration (@migrations) {
            $self->_print("Migrating '$migration->{file}'");

            next if $self->_is_dry_run;

            my $result = $migration->{migration}->execute($self->{dbh});

            $self->_finalize($migration->{no}, $result);
        }
    }
    else {
        $self->_print("Nothing to migrate");
    }

    return $self;
}

sub check {
    my $self = shift;

    $self->{verbose} = 1;

    my $db = $self->_build_db;

    if (!$db->is_prepared) {
        $self->_print('Migrations are not installed');
    }
    else {
        my $last_migration = $db->fetch_last_migration;

        if (!defined $last_migration) {
            $self->_print('No migrations found');
        }
        else {
            $self->_print(sprintf 'Last migration: %d (%s)',
                $last_migration->{no}, $last_migration->{status});

            if (my $error = $last_migration->{error}) {
                $self->_print("\n" . $error);
            }
        }
    }
}

sub fix {
    my $self = shift;

    my $db = $self->_build_db_prepared;

    my $last_migration = $db->fetch_last_migration;

    if (!$last_migration || $last_migration->{status} eq 'success') {
        $self->_print('Nothing to fix');
    }
    else {
        $self->_print("Fixing migration $last_migration->{no}");

        $db->fix_last_migration unless $self->_is_dry_run;
    }
}

sub set {
    my $self = shift;

    my $db = $self->_build_db_prepared;

    $self->_print("Creating migration $self->{migration}");

    $db->create_migration(
        no      => $self->{migration},
        created => time,
        status  => 'success'
    ) unless $self->_is_dry_run;
}

sub _detect_initial_migration {
    my $self = shift;
    my ($initial_migration) = @_;

    if ($initial_migration eq 'auto') {
        die "Error: --schema is required in auto mode\n" unless $self->{schema} && -d $self->{schema};

        my @schema_files =
          map { File::Basename::basename($_) } glob("$self->{schema}/*.sql");
        @schema_files = grep {/^(\d+).*?\.sql$/} @schema_files;

        if (@schema_files) {
            ($initial_migration) = $schema_files[-1] =~ m/^(\d+)/;
        }
        else {
            die "Error: Can't automatically detect last migration\n";
        }
    }

    die "Invalid migration '$initial_migration'\n" unless $initial_migration =~ m/^\d+$/;

    return $initial_migration;
}

sub _finalize {
    my $self = shift;
    my ($no, $result) = @_;

    my $db = $self->_build_db;

    $self->_print("Finalizing migration: $no");

    $db->create_migration(
        no      => $no,
        created => time,
        status  => $result->{success} ? 'success' : 'error',
        error   => substr($result->{error} // '', 0, 255)
    );

    die "Error: $result->{error}\n" unless $result->{success};
}

sub _build_db_prepared {
    my $self = shift;

    my $db = $self->_build_db;

    die "Error: Migrations table not found. Run <setup> command first or use --setup flag\n"
      unless $db->is_prepared;

    return $db;
}

sub _build_db {
    my $self = shift;

    my $dbh = $self->{dbh};

    if (!$dbh) {
        $dbh = DBI->connect($self->{dsn}, '', '',
            {RaiseError => 1, PrintError => 0, PrintWarn => 0});
        $self->{dbh} = $dbh;
    }

    return App::mimi::db->new(dbh => $dbh, table => $self->{table});
}

sub _print {
    my $self = shift;

    return unless $self->_is_verbose;

    print 'DRY RUN: ' if $self->_is_dry_run;

    print @_, "\n";
}

sub _is_dry_run { $_[0]->{dry_run} }
sub _is_verbose { $_[0]->{verbose} || $_[0]->_is_dry_run }

1;
__END__
=pod

=head1 NAME

App::mimi - Migrations for small home projects

=head1 SYNOPSIS

    mimi --dns 'dbi:SQLite:database.db' migrate --schema schema/

=head1 DESCRIPTION

You want to look at C<script/mimi> documentation instead. This is just an
implementation.

=head1 METHODS

=head2 C<new>

Creates new object. Duh.

=head2 C<check>

Prints current state.

=head2 C<fix>

Fixes last error migration by changing its status to C<success>.

=head2 C<migrate>

Finds the last migration number and runs all provided files with greater number.

=head2 C<set>

Manually set the last migration.

=head2 C<setup>

Creates migration table.

=head1 AUTHOR

Viacheslav Tykhanovskyi, C<viacheslav.t@gmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2017, Viacheslav Tykhanovskyi

This program is free software, you can redistribute it and/or modify it under
the terms of the Artistic License version 2.0.

This program is distributed in the hope that it will be useful, but without any
warranty; without even the implied warranty of merchantability or fitness for
a particular purpose.

=cut
