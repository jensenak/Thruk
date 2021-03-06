package Thruk::Utils::Broadcast;

=head1 NAME

Thruk::Utils::Broadcast - Broadcast Utilities Collection for Thruk

=head1 DESCRIPTION

Broadcast Utilities Collection for Thruk

=cut

use strict;
use warnings;

##############################################

=head1 METHODS

=head2 get_broadcasts($c)

  get_broadcasts($c)

return list of broadcasts for this contact

=cut
sub get_broadcasts {
    my($c) = @_;
    my $list = [];

    my $now    = time();
    my $groups = $c->cache->get->{'users'}->{$c->stash->{'remote_user'}}->{'contactgroups'};
    my @files  = glob($c->config->{'var_path'}.'/broadcast/*.json');
    return([]) unless scalar @files > 0;

    my $user_data = Thruk::Utils::get_user_data($c);
    my $already_read = {};
    if($user_data->{'broadcast'} && $user_data->{'broadcast'}->{'read'}) {
        $already_read = $user_data->{'broadcast'}->{'read'};
    }

    my $new_count = 0;
    for my $file (@files) {
        my $broadcast;
        eval {
            $broadcast = Thruk::Utils::IO::json_lock_retrieve($file);
        };
        if($@) {
            $c->log->error("could not read broadcast file $file: ".$@);
            next;
        }
        $broadcast->{'file'} = $file;
        my $basename = $file;
        $basename =~ s%.*?([^/]+\.json)$%$1%mx;
        $broadcast->{'basefile'} = $basename;
        my $allowed = 0;

        $broadcast->{'contacts'}      = Thruk::Utils::list($broadcast->{'contacts'});
        $broadcast->{'contactgroups'} = Thruk::Utils::list($broadcast->{'contactgroups'});

        # not restriced at all
        if(scalar @{$broadcast->{'contacts'}} == 0 && scalar @{$broadcast->{'contactgroups'}} == 0) {
            $allowed = 1;
        }
        # allowed for specific contacts
        if(scalar @{$broadcast->{'contacts'}}) {
            my $contacts = Thruk::Utils::array2hash($broadcast->{'contacts'});
            if($contacts->{$c->stash->{'remote_user'}}) {
                $allowed = 1;
            }
        }
        # allowed for specific contactgroups
        if(scalar @{$broadcast->{'contactgroups'}}) {
            my $contactgroups = Thruk::Utils::array2hash($broadcast->{'contactgroups'});
            for my $group (keys %{$groups}) {
                if($contactgroups->{$group}) {
                    $allowed = 1;
                    last;
                }
            }
        }
        next unless $allowed;

        # date / time filter
        if($broadcast->{'expires'}) {
            my $expires_ts = Thruk::Utils::_parse_date($c, $broadcast->{'expires'});
            if($now > $expires_ts) {
                next;
            }
        }

        if($broadcast->{'hide_before'}) {
            my $hide_before_ts = Thruk::Utils::_parse_date($c, $broadcast->{'hide_before'});
            if($now < $hide_before_ts) {
                next;
            }
        }

        $broadcast->{'new'} = 0;
        if(!defined $already_read->{$basename}) {
            $broadcast->{'new'} = 1;
            $new_count++;
        }

        push @{$list}, $broadcast;
    }

    return([]) unless $new_count > 0;

    # sort by read status and filename
    @{$list} = sort { $b->{'new'} <=> $a->{'new'} || $b->{'basefile'} cmp $a->{'basefile'} } @{$list};

    return($list);
}

########################################

=head2 update_dismiss($c)

  update_dismiss($c)

mark all broadcasts as read for the current user

=cut
sub update_dismiss {
    my($c) = @_;

    my $now = time();
    my $broadcasts = get_broadcasts($c);
    my $data = Thruk::Utils::get_user_data($c);
    $data->{'broadcast'}->{'read'} = {} unless $data->{'broadcast'}->{'read'};

    # set current date for all broadcasts
    for my $b (@{$broadcasts}) {
        $data->{'broadcast'}->{'read'}->{$b->{'basefile'}} = $now unless $data->{'broadcast'}->{'read'}->{$b->{'basefile'}};
    }

    # remove old marks for non-existing files (with a 10 day delay)
    my $clean_delay = $now - (86400 * 10);
    for my $file (keys %{$data->{'broadcast'}->{'read'}}) {
        my $ts = $data->{'broadcast'}->{'read'}->{$file};
        if(!-e $c->config->{'var_path'}.'/broadcast/'.$file && $ts < $clean_delay) {
            delete $data->{'broadcast'}->{'read'}->{$file};
        }
    }

    Thruk::Utils::store_user_data($c, $data);
    return;
}

########################################

1;

__END__

=head1 AUTHOR

Sven Nierlein, 2009-present, <sven@nierlein.org>

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
