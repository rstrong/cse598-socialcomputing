package CSE598::Project2;

our $VERSION = '0.01';

use Moose;

use Data::Dumper;
use LWP::UserAgent;
use POE;
use POE::Wheel::Run;
use POE::Filter::Reference;

has 'queue' => (is => 'rw', isa => 'ArrayRef');
has 'procs' => (is => 'rw', isa => 'Int', default => 1);
has 'debug' => (is => 'rw', isa => 'Int', default => 0);


sub start_crawling 
{
	my ($self) = @_;
	$self->logger('starting crawler...');
  	
  POE::Session->create
	(
		inline_states => 
		{
			_start => sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];
				$kernel->alias_set("Manager");
				$self->logger("Manager Starting");

				$kernel->yield('job_maker');
			},

			job_maker => sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];
				foreach my $user (@{$self->queue})
				{
					push @{$heap->{jobs}}, {text => $user} if (! $heap->{queued}->{$user});
					$heap->{queued}->{$user} = 1;

					$self->logger("$user");
				}

				$kernel->yield('job_manager');
			},

			job_manager => sub
			{
				my ($kernel, $heap) = @_[KERNEL, HEAP];
				my $epoch = time();
				my $alias = $heap->{alias};
				$heap->{epoch} = $epoch;

				$kernel->sig_child(CHLD => 'job_close');

				$heap->{stats}->{jobs} = int scalar @{$heap->{jobs}} || 0;
				$heap->{stats}->{wheels} = int scalar keys %{$heap->{job_wheels}} || 0;
				$heap->{stats}->{runningwheels} = int scalar keys %{$heap->{job_running_jobs}} || 0;
				$self->logger("Current there are $heap->{stats}->{jobs} jobs, $heap->{stats}->{wheels} wheels, $heap->{stats}->{runningwheels} running");

				# If there are no jobs for 120 seconds, assume i'm done
				if($heap->{stats}->{jobs} == 0 && $heap->{stats}->{runningwheels} == 0)
				{
					if($heap->{stats}->{done})
					{
						if(($heap->{epoch} - $heap->{stats}->{done}) > 120)
						{

							#kill every whell
							$self->logger("No active jobs for 120+ seconds.  Killing all wheels");
							foreach my $wheel (keys %{$heap->{job_wheels}})
							{
							  $heap->{job_wheels}->{$wheel}->kill() || $heap->{job_wheels}->{$wheel}->kill(9);
								$self->logger("Wheel [$wheel] killed");
							}

							$kernel->delay(cya => 10);
						}
					}
					else
					{
						$heap->{stats}->{done} = $heap->{epoch};
					}
				}
				else
				{
					delete $heap->{stats}->{done};
				}
				while(
							( ! defined $heap->{job_wheels})
							|| ( $heap->{stats}->{wheels} < $self->procs )
							|| ( ($heap->{stats}->{jobs} > $heap->{stats}->{wheels} - $heap->{stats}->{runningwheels}) && ($heap->{stats}->{wheels} < $self->procs))
						 )
				{
					$self->logger("Job manager: current $heap->{stats}->{wheels} wheels... starting job wheel");
					my $wheel;
					$wheel = POE::Wheel::Run->new
					(
						Program => \&webscraper,
						StdioFilter => POE::Filter::Reference->new(),
						CloseOnCall => 1,
						StdoutEvent => 'job_stdouterr',
						StderrEvent => 'job_stdouterr',
						CloseEvent => 'job_close',
					);
					$heap->{job_wheels}->{$wheel->ID} = $wheel;
					$heap->{job_busy}->{$wheel->ID} = 0;
					$heap->{job_busy_time}->{$wheel->ID} = '9999999999';

					$heap->{stats}->{jobs} = int scalar @{$heap->{jobs}} || 0;
					$heap->{stats}->{wheels} = int scalar keys %{$heap->{job_wheels}} || 0;
					$heap->{stats}->{runningwheels} = int scalar keys %{$heap->{job_running_jobs}} || 0;
				}
						
				foreach my $wheel_id (keys %{$heap->{job_wheels}})
				{
					if($heap->{job_busy}->{$wheel_id} == 1)
					{
						# put in code to detect dead wheels 
						#$self->logger("DEBUG: job_manager: wheel($wheel_id) busy " . ($heap->{epoch} - $heap->{job_busy_time}->{$wheel_id}) . " seconds with $heap->{job_running_jobs}->{$wheel_id}->{text}");
					}
					my $job;
					next unless ($job = shift @{$heap->{jobs}});
					$heap->{job_busy}->{$wheel_id} = 1;
					$heap->{job_busy_time}->{$wheel_id} = $heap->{epoch};
					$heap->{job_runnng_jobs}->{$wheel_id} = $job;
					$self->logger("job_manager: sending wheel($wheel_id) job: $job->{text}");
					$heap->{job_wheels}->{$wheel_id}->put($job);
				}

				$kernel->delay($_[STATE] => 10);

			},

			job_close => sub
			{
				my ($heap, $wheel_id) = @_[HEAP, ARG0];
				$self->logger("Wheel $wheel_id has finished");
				$heap->{stats}->{closedwheels}++;
				delete $heap->{job_wheels}->{$wheel_id};
				delete $heap->{job_busy}->{$wheel_id};
				delete $heap->{job_busy_time}->{$wheel_id};
				delete $heap->{job_running_jobs}->{$wheel_id};
			},

			job_stdouterr => sub
			{
				my ($kernel, $heap, $output, $wheel_id) = @_[KERNEL, HEAP, ARG0, ARG1];
				my $alias = $heap->{alias};
				$heap->{finished}++;
				$self->logger("$wheel_id finished.  I have now processed: $heap->{finished}");
				eval
				{
					$heap->{queued}->{$output->{message}} = 1;

					my $str = "uid-$output->{message},";
					open(FILE, '>>', 'friends.txt');
					if(defined $output->{content}->{friends})
					{
						if(ref $output->{content}->{friends} ne 'ARRAY')
						{
							$output->{content}->{friends} = [ $output->{content}->{friends} ];
						}
						foreach my $friend(@{$output->{content}->{friends}})
						{
							$str .= "uid-$friend,";
							push @{$heap->{jobs}}, {text => $friend} if (! $heap->{queued}->{$friend});
							$heap->{queued}->{$friend} = 1;
						}
					}
					print FILE $str . "\n";
					close(FILE);
					open(FILE, '>>', 'followers.txt');
					$str = "uid-$output->{message},";
					if(defined $output->{content}->{followers})
					{
						if(ref $output->{content}->{followers} ne 'ARRAY')
						{
							$output->{content}->{followers} = [ $output->{content}->{followers} ];
						}
						foreach my $follower(@{$output->{content}->{followers}})
						{
							$str .= "uid-$follower,";
							push @{$heap->{jobs}}, {text => $follower} if (! $heap->{queued}->{$follower});
							$heap->{queued}->{$follower} = 1;
						}
					}
					print FILE $str . "\n";
					close(FILE);
				};
				if($@)
				{
					$self->logger("ERROR: $@");
				}

				$kernel->delay('job_manager' => 1);
			},

			cya => sub
			{
				exit;
			},

		}

	);
}

sub webscraper
{
  binmode(STDOUT);
	binmode(STDIN);
	my ($filter, $return, $return_filtered, $return_debug);
	$filter = POE::Filter::Reference->new();

	my ($size, $raw, $message);
	$size = 4096;
	my $cache;
  use LWP::Simple;
  use XML::Simple;
	while( sysread(STDIN, $raw, $size))
	{
		my $message = $filter->get( [$raw] );
		my $job = shift @$message;
		my $username = $job->{text};
		my $data;
    my $p;
## Do work
    # friends
		my $friends_xml = get('http://identi.ca/api/friends/ids/' . $username . '.xml');
    # if our request was a success and at least has *some* content
		if(defined $friends_xml)
		{
			$p = XMLin($friends_xml);	
		  $data->{friends} = $p->{id};
			my $followers_xml = get('http://identi.ca/api/followers/ids/' . $username . '.xml');
			if(defined $followers_xml)
			{
				$p = ();
				$p = XMLin($followers_xml);
				$data->{followers} = $p->{id};
			}
			else
			{
				$data->{followers} = [ ];
			}
		}
		else
		{
			$data->{friends} = [ ];
			$data->{followers} = [ ];
		}
		$return = {
			"status" => "JOBFINISHED",
			"content" => $data,
			"message" => "$job->{text}",
							};
		$return_filtered = $filter->put( [$return] );
		print @$return_filtered;
	}
}


sub logger
{
	my ($self, $msg) = @_;

  if($self->debug == 1)
	{
		print "$msg\n";
	}
}






1;
__END__

=head1 NAME

CSE598::Project2 - The great new CSE598::Project2!

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';


=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use CSE598::Project2;

    my $foo = CSE598::Project2->new();
    ...

Rick Strong, C<< <rjstrong at gmail> >>

=head1 BUGS

=head1 ACKNOWLEDGEMENTS

=head1 LICENSE AND COPYRIGHT

Copyright 2010 Rick Strong.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


