# Copyright (C) 2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

package MirrorCache::Task::MirrorCheckFromStat;
use Mojo::Base 'Mojolicious::Plugin';

use Mojo::UserAgent;
use Data::Dumper;

# Task will endlessly check from latest hit that the file still still on the mirror
# This task is optional but should fix occasional mirror problems

sub register {
    my ($self, $app) = @_;
    $app->minion->add_task(mirror_check_from_stat => sub { _run($app, @_) });
}

my $DELAY = int($ENV{MIRRORCACHE_MIRROR_CHECK_DELAY} // 5);

sub _run {
    my ($app, $job, $prev_stat_id) = @_;
    my $job_id = $job->id;
    my $pref = "[check_from_stat $job_id]";
    my $id_in_notes = $job->info->{notes}{stat_id};
    $prev_stat_id = $id_in_notes if $id_in_notes;
    $prev_stat_id = 0 unless $prev_stat_id;

    my $minion = $app->minion;
    # prevent multiple scheduling tasks to run in parallel
    return $job->finish('Previous job is still active')
      unless my $guard = $minion->guard('mirror_check_from_stat', 86400);

    my $schema = $app->schema;

    print STDERR Dumper('XXXXX', $schema->resultset('Stat')->latest_hit($prev_stat_id));
    my ($stat_id, $mirror_id, $country, $url, $folder) = $schema->resultset('Stat')->latest_hit($prev_stat_id);
    my $last_run = 0;
    while ($stat_id && $stat_id > $prev_stat_id) {
        my $cnt = 0;
        $prev_stat_id = $stat_id;
        my $ua = Mojo::UserAgent->new;
        my $tx = $ua->head($url);
        my $res = $tx->res;

        if ($res->is_error) {
            $app->log->warn("Need rescan $url: " . $res->code);
            return $job->retry({delay => 10*$DELAY}) if $minion->stats->{inactive_jobs} > 100;
            $minion->enqueue('mirror_scan' => [$folder, $country] => {priority => 6});
        }

        ($stat_id, $mirror_id, $country, $url, $folder) = $schema->resultset('Stat')->latest_hit($prev_stat_id);
    }
    $job->note(stat_id => $stat_id);
    return $job->retry({delay => $DELAY});
}

1;
