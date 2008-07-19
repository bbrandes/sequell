#!/usr/bin/perl
use strict;
use warnings;
use POE qw(Component::IRC Component::IRC::Plugin::NickReclaim);
use POSIX qw(setsid); # For daemonization.

my $SERVER = 'cao';     # Local server.
my $ALT_SERVER = 'cdo'; # Our 'alternative' server.

my $nickname       = 'Henzell';
my $ircname        = 'Henzell the Crawl Bot';
my $ircserver      = 'irc.freenode.org';
my $port           = 6667;
my $channel        = '##crawl';
my @stonefiles     = ('/var/www/crawl/milestones02.txt',
                      '/home/crawl/chroot/var/games/crawl03/saves/milestones.txt',
                      '/home/crawl/chroot/var/games/crawl04/saves/milestones.txt');
my @logfiles       = ('/var/www/crawl/allgames.txt',
                      '/home/crawl/chroot/var/games/crawl04/saves/logfile',
                      # The [cdo] prefix indicates that this is a remote
                      # logfile, which we'll enter into the db with a source
                      # of "cdo", and for which we will not make announcements.
                      '[cdo]/home/henzell/cdo-logfile-0.3',
                      '[cdo]/home/henzell/cdo-logfile-0.4',
                      '[cdo]/home/henzell/cdo-logfile-svn',
                      );

my $command_dir    = 'commands/';
my $commands_file  = $command_dir . 'commands.txt';
my $seen_dir       = '/home/henzell/henzell/dat/seendb';
my %admins         = map {$_ => 1} qw/Eidolos raxvulpine toft greensnark cbus/;

my %adjective_skill_title =
  map(($_ => 1), ('Deadly Accurate', 'Spry', 'Covert', 'Unseen'));

my %commands;

do 'game_parser.pl';
require 'sqllog.pl';

# Drop process priority.
system "renice +10 $$ &>/dev/null";

# Daemonify. http://www.webreference.com/perl/tutorial/9/3.html
daemonify() unless grep($_ eq '-n', @ARGV);

my @loghandles = open_handles(@logfiles);
my @stonehandles = open_handles(@stonefiles);

if (@loghandles >= 1) {
  for my $lhand (@loghandles) {
    my $file = $lhand->[0];
    my $source_server = $lhand->[3];
    my $fh = $lhand->[1];
    cat_logfile($file, $source_server, $fh) ||
      cat_logfile($file, $source_server, $fh, -1);
  }
}

# We create a new PoCo-IRC object and component.
my $irc = POE::Component::IRC->spawn(
      nick    => $nickname,
      server  => $ircserver,
      port    => $port,
      ircname => $ircname,
) or die "Oh noooo! $!";

POE::Session->create(
      inline_states =>
      {
        check_logfile   => \&check_logfile,
      },

      package_states => [
              'main' => [ qw(_default _start irc_001 irc_public irc_msg irc_255 irc_ctcp_action irc_quit irc_join irc_part) ],
      ],
      heap => { irc => $irc },
);

$poe_kernel->run();
exit 0;

sub daemonify {
  umask 0;
  defined(my $pid = fork) or die "Unable to fork: $!";
  exit if $pid;
  setsid or die "Unable to start a new session: $!";
  # Done daemonifying.
}

sub open_handles
{
  my (@files) = @_;
  my @handles;

  for my $file (@files) {
    my ($server) = $file =~ /^\[(.*?)\]/;
    $server ||= $SERVER;

    $file =~ s/^\[.*?\]//;

    open my $handle, '<', $file or do {
      warn "Unable to open $file for reading: $!";
      next;
    };

    seek($handle, 0, 2); # EOF
    push @handles, [ $file, $handle, tell($handle), $server ];
  }
  return @handles;
}

sub newsworthy
{
  my $stone_ref = shift;

  return 0
    if $stone_ref->{type} eq 'enter'
      and grep {$stone_ref->{br} eq $_} qw/Temple/;

  return 0
    if $stone_ref->{type} eq 'unique'
      and grep {index($stone_ref->{milestone}, $_) > -1}
        qw/Terence Jessica Ijyb Blork Edmund Psyche Donald Snorg Michael/;

  return 1;
}

sub check_stonefiles
{
  for my $stone (@stonehandles) {
    check_milestone_file($stone);
  }
}

sub check_milestone_file
{
  my $href = shift;
  my $stonehandle = $href->[1];
  $href->[2] = tell($stonehandle);

  my $line = <$stonehandle>;
  # If the line isn't complete, seek back to where we were and wait for it
  # to be done.
  if (!defined($line) || $line !~ /\n$/) {
    seek($stonehandle, $href->[2], 0);
    return;
  }
  $href->[2] = tell($stonehandle);
  return unless defined($line) && $line =~ /\S/;

  my $game_ref = demunge_xlogline($line);

  return unless newsworthy($game_ref);

  my $placestring = " ($game_ref->{place})";
  if ($game_ref->{milestone} eq "escaped from the Abyss!")
  {
    $placestring = "";
  }

  $irc->yield(privmsg => $channel =>
    sprintf "%s the %s (L%s %s) %s%s",
      $game_ref->{name},
      game_skill_title($game_ref),
      $game_ref->{xl},
      $game_ref->{char},
      $game_ref->{milestone},
      $placestring
  );

  seek($stonehandle, $href->[2], 0);
}

sub game_skill_title
{
  my $game_ref = shift;
  my $title = $game_ref->{title};
  $title = skill_farming($title) if $game_ref->{turn} > 200000;
  return $title;
}

sub skill_farming
{
  my $title = shift;
  if ($adjective_skill_title{$title} || $title =~ /(?:ed|ble|ous)$/) {
    return "$title Farmer";
  } elsif ($title =~ /Crazy /) {
    $title =~ s/Crazy/Crazy Farming/;
    return $title;
  } else {
    return "Farming $title";
  }
}

sub check_all_logfiles
{
  for my $logh (@loghandles) {
    1 while tail_logfile($logh);
  }
}

sub suppress_game {
  my $g = shift;
  return ($g->{sc} <= 2000 &&
    ($g->{ktyp} eq 'quitting' || $g->{ktyp} eq 'leaving'
     || $g->{turn} < 30
     || ($g->{turn} < 1000 && $g->{place} eq 'Abyss'
         && $g->{god} eq 'Lugonu' && $g->{cls} eq 'Chaos Knight')));
}

sub tail_logfile
{
  my $href = shift;
  my $loghandle = $href->[1];

  $href->[2] = tell($loghandle);
  my $line = <$loghandle>;
  if (!defined($line) || $line !~ /\n$/) {
    seek($loghandle, $href->[2], 0);
    return;
  }
  my $startoffset = $href->[2];
  $href->[2] = tell($loghandle);
  return unless defined($line) && $line =~ /\S/;

  seek($loghandle, $href->[2], 0);

  # Add line to DB.
  add_logline($href->[0], $href->[3], $startoffset, $line);

  # If this is a local game, announce it.
  if ($href->[3] eq $SERVER) {
    my $game_ref = demunge_xlogline($line);
    if (!suppress_game($game_ref)) {
      my $output = pretty_print($game_ref);
      $output =~ s/ on \d{4}-\d{2}-\d{2}//;
      $irc->yield(privmsg => $channel => $output);
    }
  }

  1;
}

sub check_logfile
{
  $_[KERNEL]->delay('check_logfile' => 1);

  check_stonefiles();
  check_all_logfiles();
}

sub _start
{
  my ($kernel,$heap) = @_[KERNEL,HEAP];

  # We get the session ID of the component from the object
  # and register and connect to the specified server.
  my $irc_session = $heap->{irc}->session_id();
  $kernel->post( $irc_session => register => 'all' );
  $irc->plugin_add( NickReclaim =>
   	POE::Component::IRC::Plugin::NickReclaim->new( poll => 30 ));
  $kernel->post( $irc_session => connect => { } );
  undef;
}

sub irc_ctcp_action
{
  my ($kernel,$sender,$who,$where,$verbatim) = @_[KERNEL,SENDER,ARG0,ARG1,ARG2];
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];

  seen_update($nick, "acting out $nick $verbatim");
}

sub irc_quit
{
  my ($kernel,$sender,$who,$verbatim) = @_[KERNEL,SENDER,ARG0,ARG1];
  my $nick = ( split /!/, $who )[0];

  if ($verbatim ne '')
  {
    seen_update($nick, "quitting with message '$verbatim'");
  }
  else
  {
    seen_update($nick, "quitting without a message");
  }
}

sub irc_join
{
  my ($kernel,$sender,$who) = @_[KERNEL,SENDER,ARG0];
  my $nick = ( split /!/, $who )[0];

  seen_update($nick, "joining the channel");
}

sub irc_part
{
  my ($kernel,$sender,$who,$channel,$verbatim) = @_[KERNEL,SENDER,ARG0,ARG1,ARG2];
  my $nick = ( split /!/, $who )[0];

  if ($verbatim ne '')
  {
    seen_update($nick, "parting with message '$verbatim'");
  }
  else
  {
    seen_update($nick, "parting without a message");
  }
}

sub irc_001
{
  my ($kernel,$sender) = @_[KERNEL,SENDER];

  # Get the component's object at any time by accessing the heap of
  # the SENDER
  my $poco_object = $sender->get_heap();
  print "Connected to ", $poco_object->server_name(), "\n";

  # In any irc_* events SENDER will be the PoCo-IRC session
  $kernel->post( $sender => join => $channel );
  undef;
}

sub respond_to_any_msg
{
  my ($kernel, $nick, $verbatim, $sender, $channel) = @_;
  $verbatim =~ tr/'//d;
  my $output = qx!./commands/message/all_input.pl '$nick' '$verbatim'!;
  $kernel->post($sender => privmsg => $channel => $output) if $output;
}

sub irc_public
{
  my ($kernel,$sender,$who,$where,$verbatim) = @_[KERNEL,SENDER,ARG0,ARG1,ARG2];
  my $nick = ( split /!/, $who )[0];
  my $channel = $where->[0];

  my $target = $verbatim;
  $nick     =~ y/'//d;

  seen_update($nick, "saying '$verbatim'");
  respond_to_any_msg($kernel, $nick, $verbatim, $sender, $channel);

  $target =~ s/^\?\?/!learn query /;
  $target =~ s/^([!@]\w+) ?// or return;
  my $command = lc $1;

  $target   =~ s/ .*$//;
  $target   =~ y/a-zA-Z0-9//cd;
  #$target   =~ s/\d+$//;
  $target = $nick unless $target =~ /\S/;
  $target   =~ y/a-zA-Z0-9//cd;
  #$target   =~ s/\d+$//;

  if ($command eq '!load' && exists $admins{$nick})
  {
    $kernel->post( $sender => privmsg => $channel => load_commands());
  }
  elsif (exists $commands{$command})
  {
    $ENV{CRAWL_SERVER} = $command =~ /^!/ ? $SERVER : $ALT_SERVER;
    my $output =
    	$commands{$command}->(pack_args($target, $nick, $verbatim, '', ''));
    $output = substr($output, 0, 400) . "..." if length($output) > 400;
    $kernel->post( $sender => privmsg => $channel => $output);
  }

  undef;
}

sub irc_msg
{
  print "irc_msg\n";
  my ($kernel,$sender,$who,$where,$verbatim) = @_[KERNEL,SENDER,ARG0,ARG1,ARG2];
  my $nick = ( split /!/, $who )[0];

  $nick     =~ y/'//d;
  # only do learndb lookups in private messages
  $verbatim =~ /^(?:\?\?|!learn query )/ or return;

  seen_update($nick, "saying '$verbatim'");
  my $command = '!learn';

  if (exists $commands{$command})
  {
    my $output = $commands{$command}->(pack_args('', $nick, $verbatim, '', ''));
    $output = substr($output, 0, 400) . "..." if length($output) > 400;
    $kernel->post( $sender => privmsg => $nick => $output);
  }
}

sub irc_255
{
  $_[KERNEL]->yield("check_logfile");

  load_commands();

  open(my $handle, '<', 'password.txt') or warn "Unable to read password.txt: $!";
  my $password = <$handle>;
  chomp $password;

  $irc->yield(privmsg => "nickserv" => "identify $password");
}

# We registered for all events, this will produce some debug info.
sub _default
{
  my ($event, $args) = @_[ARG0 .. $#_];
  my @output = ( "$event: " );

  foreach my $arg ( @$args ) {
      if ( ref($arg) eq 'ARRAY' ) {
              push( @output, "[" . join(" ,", @$arg ) . "]" );
      } else {
              push ( @output, "'$arg'" );
      }
  }
  print STDOUT join ' ', @output, "\n";
  return 0;
}

sub load_commands
{
  %commands = ();

  my $loaded = 0;
  my $skipped = 0;

  my @command_files = do { local @ARGV = $commands_file; <>};

  foreach my $line (@command_files)
  {
    my ($command, $file) = $line =~ /^(\S+)\s+(.+)$/;
    print "Loading $command from $file...\n";

    if (0 && $file =~ /\.pl$/)
    {
      # eventually perl files should be eval'd and loaded into Henzell directly
      # for efficiency
    }
    else
    {
      $commands{$command} = sub
      {
        my $args = shift;
        handle_output(run_command($command_dir, $file, $args));
      }
    }

    print "Loaded $command.\n";
    ++$loaded;
  }

  return sprintf 'Loaded %d commands%s.', $loaded, $skipped ? sprintf(' (and %d skipped)', $skipped) : "";
}

sub pack_args
{
  join " ", map { $_ eq '' ? "''" : "\Q$_"} @_;
}

sub run_command
{
  my ($cdir, $f, $args) = @_;
  my $output = qx{./$cdir$f $args};
  if ($output =~ /\n!redirect(\S+)/) {
    return $commands{$1}->($args);
  }
  return $output;
}

sub seen_update
{
  my $nick = shift;
  my $doing = shift;

  $nick =~ y/'//d;
  $doing =~ y/'//d;

  my %seen =
  (
    nick => $nick,
    doing => $doing,
    time => time,
  );
  open my $handle, '>', "$seen_dir/\L$nick\E" or do
  {
    warn "Unable to open $seen_dir/\L$nick\E for writing: $!";
    return;
  };
  print {$handle} join(':',
                       map {$seen{$_} =~ s/:/::/g; "$_=$seen{$_}"}
                       keys %seen),
                  "\n";
}
