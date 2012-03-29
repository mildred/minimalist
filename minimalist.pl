#!/usr/bin/perl
#
# Minimalist - Minimalistic Mailing List Manager.
# Copyright (c) 1999-2005 Vladimir Litovka <vlitovka@gmail.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
# PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
# THE POSSIBILITY OF SUCH DAMAGE.

use Fcntl ':flock';	# LOCK_* constants
use integer;

$version = '2.5(4.1) (Twilight)';
$config = "/usr/local/etc/minimalist.conf";

# Program name and arguments for launching if commands in message's body
$running = $0." --body-controlled ".join ($", @ARGV);

# Lists' status bits
$OPEN = 0;
$RO = 1;
$CLOSED = 2;
$MANDATORY = 4;

@languages = ('en');

#####################################################
# Default values
#
$auth_scheme = 'password';
$adminpwd = $listpwd = '_'.$$.time.'_';		# Some pseudo-random value
$userpwd = '';
$verify = 0;		# By default eval($verify) returns false
$suffix = '';

$sendmail = '/usr/sbin/sendmail';
$delivery = 'internal';
$domain = `uname -n`; chomp $domain;
$directory = '/var/spool/minimalist';
$admin = "postmaster\@$domain";
$security = 'careful';
$archive = 'no';
$arcsize = 0;
$archpgm = 'BUILTIN';
$status = $OPEN;
$copy_sender = 'yes';
$reply_to_list = 'no';
$outgoing_from = '';
$errors_to = 'drop';
$modify_subject = 'yes';
$maxusers = 0;
$maxrcpts = 20;
$delay = 0;
$maxsize = 0;		# Maximum allowed size for message (incl. headers)
$auth_valid = 24;
$logfile = 'none';
$logmessages = 'no';
$listinfo = 'yes';
$strip_rrq = 'no';
$remove_resent = 'no';
$modify_msgid = 'no';
$xtrahdr = '';
$language = "en";
$list_gecos = '';
$background = 'no';
$to_recipient = 'no';
# Languages support
$charset = 'us-ascii';
$blocked_robots = 'CurrentlyWeAreBlockingNoRobot-Do__NOT__leaveThisBlank';	# -VTV-
$cc_on_subscribe = 'no';	# -VTV-

##
$body_controlled = 0;
$global_exit_status = 0;

#####################################################
# Various regular expressions
#
# for matching rounding spaces

$spaces = '^\s*(.*?)\s*$';

# for parsing two forms of mailing addresses:
#
# 1st form: Vladimir Litovka <doka@kiev.sovam.com>
# 2nd form: doka@kiev.sovam.com (Vladimir Litovka)

$first = '((.*?)\s*<(.*?)>)(.*)';	# $2 - gecos, $3 - address, $4 - rest
$second = '((.*?)\s*\((.*?)\))(.*)';	# $2 - address, $3 - gecos, $4 - rest

########################################################
# >>>>>>>>>>>>>>> SELF - CONFIGURING <<<<<<<<<<<<<<<<< #
########################################################

while (1) {
  if ($ARGV[0] eq '-c') {
    $config = $ARGV[1];
    shift; shift;
   }
  elsif ($ARGV[0] eq '-d') {
    $ARGV[1] =~ s|(.*)/$|$1|g;
    $config = $ARGV[1]."/minimalist.conf";
    shift; shift;
   }
  elsif ($ARGV[0] eq '--body-controlled') {
    $body_controlled = 1;
    shift;
   }
  else { last; }
 }

read_config($config, "global");
$mesender = "minimalist\@$domain";	# For substitute in X-Sender header

&InitMessages();			# Init messages

####################################################################
# >>>>>>>>>>>>>>>>>>>>>>>> CHECK CONFIGURATION <<<<<<<<<<<<<<<<<<< #
####################################################################

if ($ARGV[0] eq '-') {
  print "\nMinimalist v$version, pleased to meet you.\n".
        "Using \"$config\" as main configuration file\n\n";
  print	"================= Global configuration ================\n".
	"Directory: $directory\n".
	"Administrative password: ".($adminpwd =~ /^_.*_$/ ? "not defined\n" : "ok\n").
	"Logging: $logfile\n".
	"Log info about messages: $logmessages\n".
	"Background execution: $background\n".
	"Authentication request valid at least $auth_valid hours\n".
        "Blocked robots:";
  if ($blocked_robots !~ /__NOT__/) {
    foreach (split(/\|/, $blocked_robots)) {
      print "\n\t$_"; }
   }
  else { print " no one"; }

  if ( @blacklist ) {
    print "\nGlobal access list is:\n";
    foreach (@blacklist) {
      if ( $_ =~ s/^!(.*)//g ) { print "\t - ".$1." allowed\n" }
      else { print "\t - ".$_." disallowed\n" }
     };
   };

  print "\n\n";
  while ( $ARGV[0] ) {
    @trusted = (); $xtrahdr = ''; read_config($config, "global");

    $list = $ARGV[0];
    if ($list ne '-') {
      if (!chdir("$directory/$list")) {
        print " * There isn't such list \U$list\E\n\n";
        shift; next;
       }
      read_config("config");
      print "================= \U$list\E ================\n".
	    "Authentication scheme: $auth_scheme\n";
      if ($auth_scheme eq 'mailfrom') {
        print "Administrators: ";
        if ( @trusted ) {
	  print "\n";
          foreach (@trusted) { print "\t . ".$_."\n"; }
         }
	else { print "not defined\n"; }
       }
      else {
        print "Administrative password: ".(! $listpwd ? "empty" :
			$listpwd =~ /^_.*_$/ ? "not defined" : "Ok")."\n"; }
     }

    print "Sendmail: $sendmail\n".
        "Delivery method: $delivery".($delivery eq 'alias' ? " (destination: $delivery_alias)\n" : "\n").
	"Domain: $domain\n".
	"Security: $security\n".
	"Archiving: $archive\n".
	  ($archive ne 'no' ? " * Archiver: $archpgm\n" : "").
	  ($arcsize != 0 ? " * Maximum message size: $arcsize bytes\n" : "").
	"Status:";
    if ($status) {
      print " read-only" if ($status & $RO);
      print " closed" if ($status & $CLOSED);
      print " mandatory" if ($status & $MANDATORY);
     }
    else { print " open"; }
    print "\nCopy to sender: $copy_sender\n".
	"Reply-To list: $reply_to_list\n".
	"List GECOS: ".($list_gecos ? $list_gecos : "empty")."\n".
	"Substitute From: ".($outgoing_from ? $outgoing_from : "none")."\n".
	"Admin: $admin\n".
	"Errors from MTA: ".($errors_to eq 'drop' ? "drop" :
	          ($errors_to eq 'verp' ? "generate VERP" : "return to $errors_to"))."\n".
	"Modify subject: $modify_subject\n".
	"Modify Message-ID: $modify_msgid\n".
	"Notify on subscribe/unsibscribe event: $cc_on_subscribe\n".
	"Maximal users per list: ".($maxusers ? $maxusers : "unlimited")."\n".
	"Maximal recipients per message: ".($maxrcpts ? $maxrcpts : "unlimited")."\n".
	"Delay between deliveries: ".($delay ? $delay : "none")."\n".
	"Maximal size of message: ".($maxsize ? "$maxsize bytes" : "unlimited")."\n".
	"Strip 'Return Receipt' requests: $strip_rrq\n".
	"List information: ".($listinfo eq 'no' ? "no" : "yes".
				($listinfo ne 'yes' ? ", archive at: $listinfo" : ""))."\n".
	"Language: $language\n".
	"Charset: $charset\n".
	"Fill To: with recipient's address: $to_recipient\n".
	"Extra Header(s):".($xtrahdr ? "\n\n$xtrahdr" : " none")."\n\n";
    
    # Various checks
    $msg .= " * $directory doesn't exist!\n" if (! -d $directory);
    $msg .= " * $sendmail doesn't exist!\n" if (! -x $sendmail);
    $msg .= " * Invalid 'log messages' value '$logmessages'\n" if ($logmessages !~ /^yes$|^no$/i);
    $msg .= " * Invalid 'background' value '$background'\n" if ($background !~ /^yes$|^no$/i);
    $msg .= " * Invalid delivery method: $delivery\n" if ($delivery !~ /^internal|^alias/i);
    $msg .= " * Invalid domain '$domain'\n" if ($domain !~ /^(\w[-\w]*\.)+[a-z]{2,4}$/i);
    $msg .= " * Invalid security level '$security'\n" if ($security !~ /^none$|^careful$|^paranoid$/i);
    $msg .= " * Invalid 'copy to sender' value '$copy_sender'\n" if ($copy_sender !~ /^yes$|^no$/i);
    $msg .= " * Invalid 'modify subject' value '$modify_subject'\n" if ($modify_subject !~ /^yes$|^no$|^more$/i);
    $msg .= " * Invalid 'modify message-id' value '$modify_msgid'\n" if ($modify_msgid !~ /^yes$|^no$/i);
    $msg .= " * Invalid 'cc on subscribe' value '$cc_on_subscribe'\n" if ($cc_on_subscribe !~ /^yes$|^no$/i);
    $msg .= " * Invalid 'reply-to list' value '$reply_to_list'\n" if ($reply_to_list !~ /^yes$|^no$|\@/i);
    $msg .= " * Invalid 'from' value '$outgoing_from'\n" if ($outgoing_from !~ /\@|^$/i);
    $msg .= " * Invalid authentication request validity time: $auth_valid\n" if ($auth_valid !~ /^[0-9]+$/);
    $msg .= " * Invalid authentication scheme: $auth_scheme\n" if ($auth_scheme !~ /^mailfrom|^password/i);
    $msg .= " * Invalid archiving strategy '$archive'\n" if ($archive !~ /^no$|^daily$|^monthly$|^yearly$|^pipe$/i);
    $msg .= " * Invalid 'strip rrq' value '$strip_rrq'\n" if ($strip_rrq !~ /^yes$|^no$/i);
    $msg .= " * Invalid 'remove resent' value '$remove_resent'\n" if ($remove_resent !~ /^yes$|^no$/i);
    $msg .= " * Invalid language '$language'\n" if (!grep(/^$language$/, @languages));
    $msg .= " * Invalid 'to recipient' value '$to_recipient'\n" if ($to_recipient !~ /^yes$|^no$/i);
    if ($archive eq 'pipe') {
      ($arpg, ) = split(/\s+/, $archpgm, 2);
      $msg .= " * $arpg doesn't exists!\n" if (! -x $arpg);
     }

    goto CfgCheckEnd if ($msg);
    shift;
   }

  CfgCheckEnd:

  print "\t=== FAILURE ===\n\nErrors are:\n".$msg."\n" if ($msg);
  print "\t=== WARNING ===\n\nConfiguration file '$config' does not exist.\n\n" if (! -f $config);
  exit 0;
 }

####################################################################
# >>>>>>>>>>>>>>>>>>>>>>>>> START HERE <<<<<<<<<<<<<<<<<<<<<<<<<<< #
####################################################################

$list = $ARGV[0];
$auth_seconds = $auth_valid * 3600;	# Convert hours to seconds

while (<STDIN>) {
  s/\r//g;		# Remove Windooze's \r, it is safe to do this
  $message .= $_;
 }
($header, $body) = split(/\n\n/, $message, 2); $header .= "\n";

undef $message;		# Clear memory, it doesn't used anymore

$from = $reply = $sender = $xsender = $subject = '';

# Check SysV-style "From ". Stupid workaround for messages from robots, but
# with human-like From: header. In most cases "From " is the only way to
# find out envelope sender of message.
if ($header =~ /^From (.*)\n/i) {
  exit 0 if ($1 =~ /(MAILER-DAEMON|postmaster)@/i); }

# Extract From:
if ($header =~ /(^|\n)from:\s+(.*\n([ \t]+.*\n)*)/i) {
  $from = $2; $from =~ s/$spaces/$1/ogs;
  $from =~ s/\n//g; $from =~ s/\s{2,}/ /g; }

# If there is Reply-To, use this address for replying
if ($header =~ /(^|\n)reply-to:\s+(.*\n([ \t]+.*\n)*)/i) {
  $reply = $2; $reply =~ s/$spaces/$1/gs; }

# Sender and X-Sender are interesting only when generated by robots
# (Minimalist, MTA, etc), which (I think :) don't produce multiline headers.

if ($header =~ /(^|\n)sender: (.*)\n/i) { $sender = $2; }
if ($header =~ /(^|\n)x-sender: (.*)\n/i) { $xsender = $2; }
 
$mailto = ( $reply eq '' ? $from : $reply );

# Preparing From:
if ($from =~ s/$first/$3/og) { ($gecos = $2) =~ s/$spaces/$1/gs;}
elsif ($from =~ s/$second/$2/og) { ($gecos = $3) =~ s/$spaces/$1/gs; }
$from =~ s/\s+//gs; $from = lc($from);

exit 0 if (($xsender eq $mesender) || ($from eq $mesender));	# LOOP detected
exit 0 if (($from =~ /(MAILER-DAEMON|postmaster)@/i) ||		# -VTV-
	   ($sender =~ /(MAILER-DAEMON|postmaster)@/i) ||
	   ($xsender =~ /(MAILER-DAEMON|postmaster)@/i));	# ignore messages from MAILER-DAEMON

exit 0 if ( $header =~ /^($blocked_robots):/);			# disable loops from robots -VTV-

foreach (@blacklist) {				# Parse access control list
  if ( $_ =~ s/^!(.*)//g ) {
    last if ( $from =~ /$1$/i || $sender =~ /$1$/i || $xsender =~ /$1$/i) }
  else {
    exit if ( $from =~ /$_$/i || $sender =~ /$_$/i || $xsender =~ /$_$/i) }
 };

$qfrom = quotemeta($from);	# For use among with 'grep' function

# Look for user's supplied password
# in header (in form: '{pwd: blah-blah}' )
while ($header =~ s/\{pwd:[ \t]*(\w+)\}//i) {
  $userpwd = $1; }
# in body, as very first '*password: blah-blah'
if (!$userpwd && $body =~ s/^\*password:[ \t]+(\w+)\n+//i) {
  $userpwd = $1; }

# Get (multiline) subject
if ($header =~ /(^|\n)subject:[ \t]+(.*\n([ \t]+.*\n)*)/i) {
  $subject = $2; $subject =~ s/$spaces/$1/gs; }

$body =~ s/\n*$/\n/g;
$body =~ s/\n\.\n/\n \.\n/g;	# Single '.' treated as end of message

#########################################################################
########################## Message to list ##############################
#
if ($list) {

 if (! -d "$directory/$list" ) {
   $msg = <<_EOF_ ;
To: $admin
Subject: Possible error in system settings

ERROR:
    Minimalist was called with the '$list' argument, but there is no such
    list in '$directory'.

SOLUTION:
    Check your 'aliases' file - there is a possible typo.

_EOF_
   goto SendMessage;	# Send message and exit.
  }

 ##################################
 # Go to background, through fork #
 ##################################

 if ($background eq 'yes') {

   $msg = <<_EOF_ ;
To: $admin
Subject: Can not fork

ERROR:
    Minimalist can not fork due to the following reason:
_EOF_
   $forks = 0;

   FORK: {

   if (++$forks > 4) {
     $msg .= "\n    Can't fork for more than 5 times\n\n";
     goto SendMessage;
    }
   if ($pid = fork) {
     # OK, parent here, exiting
     exit 0;
    }
   elsif (defined $pid) {
     # OK, child here. Detach and do
     close STDIN;
     close STDOUT;
     close STDERR;
    }
   elsif ($! =~ /No more process/i) {
     # EAGAIN, supposedly recoverable fork error, but no more than 5 times
     sleep 5;
     redo FORK;
    }
   else {
     # weird fork error, exiting
     $msg .= "\n    $!\n\n";
     goto SendMessage;
    }
   } # Label FORK
  }  # if ($background)

 chdir("$directory/$list");
 read_config("config");

 # Remove or exit per List-ID
 exit 0 if ($header =~ s/(^|\n)list-id:\s+(.*)\n/$1/i && $2 =~ /$list.$domain/i);

 if ($modify_subject ne 'no') {
   $orig_subj = $subject;
   if ($modify_subject eq 'more') {	# Remove leading "Re: "
     $subject =~ s/^.*:\s+(\[$list\])/$1/ig }
   else {				# change anything before [...] to Re:
     $subject =~ s/^(.*:\s+)+(\[$list\])/Re: $2/ig; }

   # Modify subject if it don't modified before
   if ($subject !~ /^(.*:\s+)?\[$list\] /i) {
     $subject = "[$list] ".$subject; }
  }
  
 open LIST, "list" and do {
   while ($ent = <LIST>) {
     if ( $ent && $ent !~ /^#/ ) {
       chomp($ent); $ent = lc($ent);

       # Get and remove per-user settings from e-mail
       $ent =~ s/(>.*)$//; $userSet = $1;

       # Check for '+' (write access) or '-' (read only access)
       if ($userSet =~ /-/) { push (@readonly, $ent); }
       elsif ($userSet =~ /\+/) { push (@writeany, $ent); }

       # If user's maxsize
       if ($userSet !~ /#ms([0-9]+)/) { undef $usrMaxSize }
       else { $usrMaxSize = $1 }

       # If suspended (!) or maxsize exceeded, do not put in @members
       if ($userSet =~ /!/ || ($usrMaxSize && length($body) > $usrMaxSize)) {
         push (@rw, $ent); }
       else {
         push (@members, $ent); }
      }
    }
   close LIST;
  };
 
 # If sender isn't admin, prepare list of allowed writers
 if (($security ne 'none') && !eval($verify)) {
   push (@rw, @members);
   open LIST, "list-writers" and do {
     while ($ent = <LIST>) {
       if ( $ent && $ent !~ /^#/ ) {
	 chomp($ent); $ent = lc($ent);
	 
         # Get and remove per-user settings from e-mail
         $ent =~ s/(>.*)$//; $userSet = $1;

         # Check for '+' (write access) or '-' (read only access)
         if ($userSet =~ /-/) { push (@readonly, $ent); }
         elsif ($userSet =~ /\+/) { push (@writeany, $ent); }

	 push (@rw, $ent); }
      }
     close LIST;
    }
  }

 # If sender isn't admin and not in list of allowed writers
 if (($security ne 'none') && !eval($verify) && !grep(/^$qfrom$/i, @rw)) {
   $msg = <<_EOF_ ;
To: $mailto
Subject: $subject

$msgtxt{'2'.$language} ($from) $msgtxt{'3'.$language} ($list) $msgtxt{'3.1'.$language} minimalist\@$domain $msgtxt{'4'.$language}
===========================================================================
$body
===========================================================================
_EOF_
  ### dirty hack to suppress "you're not subscripted" ###
   $msg = '';
  } 

 # If list or sender in read-only mode and sender isn't admin and not
 # in allowed writers
 elsif (($status & $RO || grep(/^$qfrom$/i, @readonly)) && !eval($verify) && !grep(/^$qfrom$/i, @writeany)) {
   $msg = <<_EOF_ ;
To: $mailto
Subject: $subject

$msgtxt{'5'.$language} ($from) $msgtxt{'5.1'.$language}
===========================================================================
$body
===========================================================================
_EOF_
  }
 elsif ($maxsize && (length($header) + length($body) > $maxsize)) {
   $msg = <<_EOF_ ;
To: $mailto
Subject: $subject

$msgtxt{'6'.$language} $maxsize $msgtxt{'7'.$language}

$header
_EOF_
  }
 else {		# Ok, all checks done.

   &logCommand("L=\"$list\" T=\"$orig_subj\" S=".(length($header) + length($body))) if ($logmessages ne 'no');

   $archive = 'no' if ($arcsize && length ($body) > $arcsize);
   if ($archive eq 'pipe') { arch_pipe(); }
   elsif ($archive ne 'no') { archive(); }

   # Extract and remove all recipients of message. This information will be
   # used later, when sending message to members except those who already
   # received this message directly.

   if ($header =~ s/(^|\n)to:\s+(.*\n([ \t]+.*\n)*)/$1/i) { $rc = $2 }
   if ($header =~ s/(^|\n)cc:\s+(.*\n([ \t]+.*\n)*)/$1/i) { $rc .= ",".$2 }

   if ($rc) {
     @pre_recip = split(/,/, $rc);
     foreach $rc (@pre_recip) {
       if ($rc =~ s/$first/$4/) { push (@recip, $1) }
       elsif ($rc =~ s/$second/$4/) { push (@recip, $1) }
       else { $rc =~ s/$spaces/$1/; push (@recip, $rc); }
      }
    }

   # Search for user's supplied GECOS
   foreach $trcpt (@recip) {
     $trcpt =~ s/$spaces/$1/gs;
     next if (! $trcpt);  # In case "To: e@mail, \n" - don't push spaces, which are between ',' and '\n'

     push(@hdrcpt, $trcpt);

     if ( $trcpt =~ s/$first/$3/g ) { ($tmp_to_gecos = $2) =~ s/$spaces/$1/gs; }
     elsif ( $trcpt =~ s/$second/$2/g ) { ($tmp_to_gecos = $3) =~ s/$spaces/$1/gs; }
     push(@rcpts, $trcpt = lc($trcpt));

     $to_gecos = $tmp_to_gecos if ($tmp_to_gecos && $trcpt eq $list.'@'.$domain);
     $tmp_to_gecos = '';
    }

   # If there was To: and Cc: headers, put them back in message's header
   if (@hdrcpt && $to_recipient eq 'no') {
     # If there is administrator's supplied GECOS, use it instead of user's supplied
     if ($list_gecos) {
       for ($i=0; $i<@hdrcpt; $i++) {
	 if ($hdrcpt[$i] =~ /$list\@$domain/) {	# Yes, list's address
	   $hdrcpt[$i] =~ s/$second/$2/g if (! ($hdrcpt[$i] =~ s/$first/$3/g));
	   $hdrcpt[$i] = "$list_gecos <$hdrcpt[$i]>";
	  }
	}
       $to_gecos = $list_gecos;
      }

     chomp $header;
     $header .= "\nTo: $hdrcpt[0]\n";
     if (@hdrcpt > 1) {
       $header .= "Cc: $hdrcpt[1]";
       for ($i=2; $i<@hdrcpt; $i++) {
	 $header .= ",\n\t$hdrcpt[$i]";
	}
       $header .= "\n";
      }
    }

   # Remove conflicting headers
   $header =~ s/(^|\n)x-list-server:\s+.*\n([ \t]+.*\n)*/$1/ig;
   $header =~ s/(^|\n)precedence:\s+.*\n/$1/ig;

   if ($remove_resent eq 'yes') {
     $header =~ s/(^|\n)(resent-.*\n([ \t]+.*\n)*)*/$1/ig;
    }

   if ($strip_rrq eq 'yes') {		# Return Receipt requests
     $header =~ s/return-receipt-to:\s+.*\n//ig;
     $header =~ s/disposition-notification-to:\s+.*\n//ig;
     $header =~ s/x-confirm-reading-to:\s+.*\n//ig;
    }

   if ($modify_msgid eq 'yes') {	# Change Message-ID in outgoing message
     $header =~ s/message-id:\s+(.*)\n//i;
     $old_msgid = $1; $old_msgid =~ s/$first/$3/g;
     $msgid = "MMLID_".int(rand(100000));
     $header .= "Message-ID: <$msgid-$old_msgid>\n";
    }

   chomp ($header);
   $header .= "\nPrecedence: list\n";		# For vacation and similar programs

   # Remove original Reply-To unconditionally, set configured one if it is
   $header =~ s/(^|\n)reply-to:\s+.*\n([ \t]+.*\n)*/$1/ig;
   if ($reply_to_list eq 'yes') { $header .= "Reply-To: $to_gecos <$list\@$domain>\n"; }
   elsif ($reply_to_list ne 'no') { $header .= "Reply-To: $reply_to_list\n"; }

   if ($modify_subject ne 'no') {
     $header =~ s/(^|\n)subject:\s+.*\n([ \t]+.*\n)*/$1/ig;
     $header .= "Subject: $subject\n";
    }
   if ($outgoing_from ne '') {
     $header =~ s/(^|\n)from:\s+.*\n([ \t]+.*\n)*/$1/ig;
     $header .= "From: $outgoing_from\n";
    }
   if ($listinfo ne 'no') {
     # --- Preserve List-Archive if it's there
     if ($header =~ s/(^|\n)List-Archive:\s+(.*\n([ \t]+.*\n)*)/$1/i) { $listarchive = $2; }
     # --- Remove List-* headers
     $header =~ s/(^|\n)(List-.*\n([ \t]+.*\n)*)*/$1/ig;

     $header .= "List-Help: <mailto:minimalist\@$domain?subject=help>\n";
     $header .= "List-Subscribe: <mailto:minimalist\@$domain?subject=subscribe%20$list>\n";
     $header .= "List-Unsubscribe: <mailto:minimalist\@$domain?subject=unsubscribe%20$list>\n";
     $header .= "List-Post: <mailto:$list\@$domain>\n";
     $header .= "List-Owner: <mailto:$list-owner\@$domain>\n";

     if ($listinfo ne 'yes') {
       $header .= "List-Archive: $listinfo\n"; }
     elsif ($listarchive) {
       $header .= "List-Archive: $listarchive\n"; }
    }
   $header .= "List-ID: <$list.$domain>\n";
   $header .= "X-List-Server: Minimalist v$version <http://www.mml.org.ua/>\n";
   $header .= "X-BeenThere: $list\@$domain\n";	# This header deprecated due to RFC2919 (List-ID)
   if ($xtrahdr) {
     chomp $xtrahdr; $header .= "$xtrahdr\n"; }

   &do_MIME_message;

   if ($delivery eq 'internal') {

     if ($copy_sender eq 'no') { push (@rcpts, $from) }	# @rcpts will be _excluded_

     # Sort by domains
     @members = sort @t = Invert ('@', '!', @members);
     @rcpts =   sort @t = Invert ('@', '!', @rcpts);

     for ($r=0, $m=0; $m < @members; ) {
       if ($r >= @rcpts || $members[$m] lt $rcpts[$r]) {
	 push (@recipients, $members[$m++]); }
       elsif ($members[$m] eq $rcpts[$r]) { $r++; $m++; }
       elsif ($members[$m] gt $rcpts[$r]) { $r++ };
      }

     @recipients = Invert ('!', '@', @recipients);

     #########################################################
     # Send message to recipients ($maxrcpts per message)

     $rcs = 0;

     foreach $one (@recipients) {
       if ($rcs == $maxrcpts) {
	 sendPortion();
	 $bcc = ''; $rcs = 0;	# Clear counters
	 sleep $delay if ($delay);
	}
       if ($one ne '') {
	 $bcc .= "$one "; $rcs++; }
      }

     sendPortion() if ($bcc ne '');	# Send to rest subscribers
    }
   else {	# Alias delivery
     open MAIL, "| $sendmail $delivery_alias";
     print MAIL $header."\n".$body;
     close MAIL;
    }

   $msg = '';	# Clear message, don't send anything anymore
  }

} else {

#########################################################################
######################## Message to Minimalist ##########################
#
# Allowed commands:
#	subscribe <list> [<e-mail>]
#	unsubscribe <list> [<e-mail>]
#	mode <list> <e-mail> <set> [<setParam>]
#	suspend <list>
#	resume <list>
#	maxsize <list> <maxsize>
#	auth <code>
#	which [<e-mail>]
#	info [<list>]
#	who <list>
#	body
#	help

 $subject =~ s/^.*?: //g;	# Strip leading 'Anything: '

 $list = ''; $email = '';
 ($cmd, $list, $email) = split (/\s+/, $subject, 3);
 $cmd = lc($cmd); $list = lc($list);

 if (!$cmd || $cmd eq 'body') {	# Commands are in message's body
   @bodyCommands = split (/\n+/, $body);
   $header =~ s/(^|\n)subject:[ \t]+.*?\n/$1/i;
   $header .= "X-MML-Password: {pwd: $userpwd}\n" if ($userpwd);

   $errors = 0;
   foreach $cmd (@bodyCommands) {
     last if ($cmd =~ /^(stop|exit)/i);

     open MML, "|$running";
     print MML $header."Subject: $cmd\n\n";
     close MML;
     last if ($? && ++$errors > 9);	# Exit if too many "bad syntax" errors
    }
   exit 0;
  }

 if ($cmd eq 'mode') {
   ($eml, $usermode) = split (/\s+/, $email, 2);
   $email = $eml;
  }

 if ($email ne '') {
   $email =~ s/$first/$3/g || $email =~ s/$second/$2/g ;
   $email =~ s/\s+//gs; $email = lc($email);
  }

 $msg = "To: $mailto\n".
	"Subject: Re: $subject\n".
	"X-Sender: $mesender\n".
	"X-List-Server: Minimalist v$version <http://www.mml.org.ua/>\n";
 
 if ($cmd eq 'help') {
   $msg .= "\n".$msgtxt{'1'.$language};
  ### dirty hack to suppress help message ###
   $msg = '';
 }

 elsif ($cmd eq 'auth' && ($authcode = $list)) {
   ($cmd, $list, $email, $cmdParams) = getAuth($authcode);

   if ($cmd) {		# authentication code is valid
     chdir "$directory/$list";
     read_config("config");

     $msg .= "List-ID: <$list.$domain>\n";
     $owner = "$list-owner\@$domain";

     if ($cmd eq 'subscribe' || $cmd eq 'unsubscribe') {
       $ok = eval("$cmd(0)"); }
     else {	# suspend, resume, maxsize
       $ok = &chgSettings($cmd, $list, $email, $cmdParams); }

     if ($ok && $logfile ne 'none') {
       &logCommand("$cmd $list$suffix".($email eq $from ? "" : " $email")." $cmdParams"); }
    }
   else { $msg .= $msgtxt{'8'.$language}.$authcode.$msgtxt{'9'.$language} }
  }

 elsif ($cmd eq 'which') {
   $email = $list;	# $list means $email here
   if ($email && ($email ne $from) && !eval($verify)) { $msg .= $msgtxt{'10'.$language}; }
   else {
     &logCommand($subject) if ($logfile ne 'none');
     $email = $from if (! $email);

     $msg .= $msgtxt{'11'.$language}."$email:\n\n";

     # Quote specials (+)
     $email =~ s/\+/\\\+/g;	# qtemail

     chdir $directory;
     opendir DIR, ".";
     while ($dir = readdir DIR) {
       if (-d $dir && $dir !~ /^\./) {	# Ignore entries starting with '.'
	 foreach $f ("", "-writers") {
           open LIST, "$dir/list".$f and do {
             while (<LIST>) {
               chomp($_);
               if ($_ =~ /$email(>.*)?$/i) {
	         $msg .= "* \U$dir\E$f".&txtUserSet($1);
		 last;
		}
              }
             close LIST;
	    }	# open LIST
	  }	# foreach
        }
      }		# readdir
     closedir DIR;
    }
  }

 else {		# Rest commands use list's name as argument
 
 if ($list =~ s/^(.*?)(-writers)$/$1/) {	# -writers ?
   $suffix = $2; }

 %cmds = (cSub => 'subscribe',
          cUnsub => 'unsubscribe',
          cInfo => 'info',
          cWho => 'who',
          cSuspend => 'suspend',
          cResume => 'resume',
          cMaxsize => 'maxsize',
          cMode => 'mode');

 $qcmd = quotemeta($cmd);
 if (! grep(/^$qcmd$/, %cmds)) { # Bad syntax or unknown instruction.
   goto BadSyntax; }
 elsif ( ($list ne '') && (! -d "$directory/$list") ) {
   $msg .= $msgtxt{'12'.$language}." \U$list\E ".$msgtxt{'13'.$language}.
     " minimalist\@$domain ".$msgtxt{'14'.$language};
  }
 elsif ( ($cmd eq $cmds{cSub} || $cmd eq $cmds{cUnsub}) && ($list ne '') ) {

   chdir "$directory/$list";
   read_config("config");

#   exit 0 if ($header =~ /(^|\n)list-id:\s+(.*)\n/i && $2 =~ /$list.$domain/i);

   $msg .= "List-ID: <$list.$domain>\n";
   $owner = "$list-owner\@$domain";

   # Check for possible loop
   $melist = "$list\@$domain";
   exit 0 if (($from eq $melist) || ($email eq $me) || ($email eq $melist));

   if (eval($verify)) {
     &logCommand($subject) if (eval("$cmd(1)") && $logfile ne 'none');
    }
   elsif (($email ne '') && ($email ne $from)) {
     $msg .= $msgtxt{'15'.$language}; }
   elsif (($cmd eq $cmds{cSub}) && ($status & $CLOSED)) {
     $msg .= $msgtxt{'16'.$language}.$owner; }
   elsif (($cmd eq $cmds{cUnsub}) && ($status & $MANDATORY)) {
     $msg .= $msgtxt{'17'.$language}.$owner; }
   else {
     if ($security ne 'paranoid') {
       &logCommand($subject) if (eval("$cmd(0)") && $logfile ne 'none'); }
     else {
       $msg = genAuthReport( genAuth() );
      }
    }
  }	# subscribe/unsubscribe

 elsif ($cmd eq $cmds{cInfo}) {
   &logCommand($subject) if ($logfile ne 'none');
   if ($list ne '') {
     $msg .= $msgtxt{'23'.$language}." \U$list\E\n\n";
     $msg .= read_info("$directory/$list/info");
    }
   else {
     $msg .= $msgtxt{'24'.$language}." $domain:\n\n";
     if (open(INFO, "$directory/lists.lst")) {
       while (<INFO>) {
         $msg .= $_ if (! /^#/); }
       close INFO;
      }
    }
  }

 elsif (($cmd eq $cmds{cWho}) && ($list ne '')) {
   chdir "$directory/$list";
   read_config("config");
   $msg .= "List-ID: <$list.$domain>\n";

   if (eval($verify)) {
     &logCommand($subject) if ($logfile ne 'none');
     $msg .= $msgtxt{'25'.$language}." \U$list\E$suffix:\n\n";
     if (open(LIST, "list".$suffix)) {
       while ($ent = <LIST>) {
         push (@whoers, $ent) if ($ent !~ /^#/ && chomp ($ent)) }
       if (@whoers) {
         @whoers = sort @t = Invert ('@', '!', @whoers);
	 @whoers = Invert ('!', '@', @whoers);
	 foreach $ent (@whoers) {
	   $ent =~ s/(>.*)?$//;
	   $msg .= $ent.&txtUserSet($1);
	  }
	}
       close LIST;
      }
     $msg .= $msgtxt{'25.1'.$language}.@whoers."\n";
    }
   else { $msg .= $msgtxt{'26'.$language}; }
  }

 # NOTE: $email here means value of maxsize
 elsif ( ( ($cmd eq $cmds{cSuspend} || $cmd eq $cmds{cResume}) && $list) ||
           ($cmd eq $cmds{cMaxsize}) && $list && $email =~ /[0-9]+/ ) {

   chdir "$directory/$list";
   read_config("config");
   $msg .= "List-ID: <$list.$domain>\n";

   if (eval($verify) || $security ne 'paranoid') {
     &logCommand($subject)
       if (&chgSettings($cmd, $list, $from, $email) && $logfile ne 'none');
    }
   else { $msg = genAuthReport( genAuth($email) ); }
  }
 
 elsif (($cmd eq $cmds{cMode}) && $list && $email &&
        ($usermode =~ s/^(reset|reader|writer|usual|suspend|resume|maxsize)\s*([0-9]+)?$/$1/i) ) {
   $cmdParams = $2;

   chdir "$directory/$list";
   read_config("config");
   $msg .= "List-ID: <$list.$domain>\n";

   # Only administrator allowed to change settings
   if (eval($verify)) {
     &logCommand($subject)
       if (&chgSettings($usermode, $list, $email, $cmdParams) && $logfile ne 'none');
    }
   else { # Not permitted to set usermode
     $msg .= $msgtxt{'44'.$language};
    }
  }
 else {
   BadSyntax:		# LABEL HERE !!!
     $msg =~ s/(^|\n)subject:\s+(.*\n([ \t]+.*\n)*)/$1/i;
     $msg .= "Subject: ".$msgtxt{'27.0'.$language}."\n\n * $subject *\n".$msgtxt{'27'.$language};
     $global_exit_status = 10 if ($body_controlled);
    ### dirty hack to suppress help message ###
     $msg = '';
  }
 }	# Rest commands

 cleanAuth();		# Clean old authentication requests
}

SendMessage:

if ($msg ne '') {

 $msg = "From: Minimalist Manager <$me>\n".
	"MIME-Version: 1.0\n".
	"Content-Type: text/plain; charset=$charset\n".
	"Content-Transfer-Encoding: 8bit\n".
	$msg;
  $msg =~ s/\n*$//g;

  open MAIL, "| $sendmail -t -f $me";
  print MAIL "$msg\n\n-- \n".$msgtxt{'28'.$language}."\n";
  close MAIL;
 }

exit $global_exit_status;

#########################################################################
######################## Supplementary functions ########################

# Convert plain/text messages to multipart/mixed or
# append footer to existing MIME structure
#
sub do_MIME_message {

 $footer = read_info("$directory/$list/footer");
 return if (! $footer);	# If there isn't footer, do nothing

 $encoding = '7bit';

 $header =~ /(^|\n)Content-Type:[ \t]+(.*\n([ \t]+.*\n)*)/i;
 $ctyped = $2;
 # Check if there is Content-Type and it isn't multipart/*
 if (!$ctyped || $ctyped !~ /^multipart\/(mixed|related)/i) {
   $ctyped =~ /charset="?(.*?)"?[;\s]/i;
   $msgcharset = lc($1);
   $encoding = $2
     if ($header =~ /(^|\n)Content-Transfer-Encoding:[ \t]+(.*\n([ \t]+.*\n)*)/i);

   # If message is 7/8bit text/plain with same charset without preset headers in
   # footer, then simply add footer to the end of message
   if ($ctyped =~ /^text\/plain/i && $encoding =~ /[78]bit/i &&
       ($charset eq $msgcharset || $charset eq 'us-ascii') &&
       $footer !~ /^\*hdr:[ \t]+/i) {
     $body .= "\n\n".$footer;
    }
   else {
     # Move Content-* fields to MIME entity
     while ($header =~ s/(^|\n)(Content-[\w\-]+:[ \t]+(.*\n([ \t]+.*\n)*))/$1/i) {
       push (@ctypeh, $2) 
      }
     $boundary = "MML_".time()."_$$\@".int(rand(10000)).".$domain";
     $header .= "MIME-Version: 1.0\n" if ($header !~ /(^|\n)MIME-Version:/);
     $header .= "Content-Type: multipart/mixed;\n\tboundary=\"$boundary\"\n";

     if ($footer !~ s/^\*hdr:[ \t]+// && $charset) {
       $footer = "Content-Type: text/plain; charset=$charset; name=\"footer.txt\"\n".
		 "Content-Disposition: inline\n".
                 "Content-Transfer-Encoding: 8bit\n\n".$footer;
      }

     # Make body
     $body = "\nThis is a multi-part message in MIME format.\n".
             "\n--$boundary\n".
	     join ('', @ctypeh).
	     "\n$body".
	     "\n--$boundary\n".
	     $footer.
	     "\n--$boundary--\n";
    }
  }
 else {	# Have multipart message
   $ctyped =~ /boundary="?(.*?)"?[;\s]/i;
   $level = 1; $boundary[0] = $boundary[1] = $1; $pos = 0;

   THROUGH_LEVELS:
   while ($level) {
     $hdrpos = index ($body, "--$boundary[$level]", $pos) + length($boundary[$level]) + 3;
     $hdrend = index ($body, "\n\n", $hdrpos);
     $entity_hdr = substr ($body, $hdrpos,  $hdrend - $hdrpos)."\n";

     $entity_hdr =~ /(^|\n)Content-Type:[ \t]+(.*\n([ \t]+.*\n)*)/i;
     $ctyped = $2;

     if ($ctyped =~ /boundary="?(.*?)"?[;\s]/i) {
       $level++; $boundary[$level] = $1; $pos = $hdrend + 2;
       next;
      }
     else {
       $process_level = $level;
       while ($process_level == $level) {
	 # Looking for nearest boundary
	 $pos = index ($body, "\n--", $hdrend);

	 # If nothing found, then if it's last entity, add footer
	 # to end of body, else return error
	 if ($pos == -1) {
	   if ($level == 1) { $pos = length ($body); }
	   last THROUGH_LEVELS;
	  }

	 $hdrend = index ($body, "\n", $pos+3);
	 $bound = substr ($body, $pos+3, $hdrend-$pos-3);

	 # End of current level?
	 if ($bound eq $boundary[$level]."--") { $difflevel = 1; }
	 # End of previous level?
	 elsif ($bound eq $boundary[$level-1]."--") { $difflevel = 2; }
	 else { $difflevel = 0; }

	 if ($difflevel) {
	   $pos += 1; $level -= $difflevel;
	   if ($level > 0) {
	     $pos += length ("--".$boundary[$level]."--"); }
	  }
	 # Next part of current level
	 elsif ($bound eq "$boundary[$level]") {
	   $pos += length ("$boundary[$level]") + 1;
	  }
	 # Next part of previous level
	 elsif ($bound eq "$boundary[$level-1]") {
	   $pos++; $level--;
	  }
	 # else seems to be boundary error, but do nothing
	}	 
      }
    }	# while THROUGH_LEVELS

   if ($pos != -1) {
     # If end of last level not found, workaround this
     if ($pos == length($body) && $body !~ /\n$/) {
       $body .= "\n"; $pos++; }

     # Modify last boundary - it will not be last
     substr($body, $pos, length($body)-$pos) = "--$boundary[1]\n";

     # Prepare footer and append it with really last boundary
     if ($footer !~ s/^\*hdr:[ \t]+// && $charset) {
       $footer = "Content-Type: text/plain; charset=$charset; name=\"footer\"\n".
                 "Content-Transfer-Encoding: 8bit\n\n".$footer;
      }
     $body .= $footer."\n--$boundary[1]--\n";
    }
   # else { print "Non-recoverable error while processing input file\n"; }
  }
}

#................... SUBSCRIBE .....................
sub subscribe {

 my ($trustedcall) = @_;
 my $cc;

 # Clear any spoofed settings
 $email =~ s/>.*$//;

 if ($email) { $cc = "$email," if ($email ne $from); }
 else { $email = $from; }

 if (open LIST, "list".$suffix) {
   $users .= $_ while (<LIST>);
   close LIST;
   @members = split ("\n", $users);
   $eml = quotemeta($email);
   # Note comments (#) and settings
   if (grep(/^#*$eml(>.*)?$/i, @members)) {
     $deny = 1;
     $cause = $msgtxt{'29'.$language}." \U$list\E$suffix";
    }
   elsif (!$trustedcall && $maxusers > 0 ) {
     if ($suffix) { open LIST, "list" }		# Count both readers/writers and writers
     else { open LIST, "list-writers" }
     $others .= $_ while (<LIST>);
     close LIST;
     push (@members, split ("\n", $others));
     if (@members >= $maxusers) {
       $deny = 1; $cc .= "$owner,";
       $cause = $msgtxt{'30'.$language}.$maxusers.") @ \U$list\E";
      }
    }
   open LIST, ">>list".$suffix if (!$deny);
  }
 else { open LIST, ">list".$suffix; } 

 $cc .= "$owner," if ( $cc_on_subscribe =~ /yes/i && ! $deny);

 if ($cc) {
   chop $cc;
   $msg .= "Cc: $cc\n";
  }

 $msg .= $msgtxt{'40'.$language}." $email,\n\n";

 if (! $deny) {
   &lockf(LIST, 'lock'); print LIST "$email\n"; &lockf(LIST);
   $msg .= $msgtxt{'31'.$language}." \U$list\E$suffix ".$msgtxt{'32'.$language}.
           read_info("$directory/$list/info");
  }
 else {
   $msg .= <<_EOF_ ;
$msgtxt{'33'.$language} \U$list\E$suffix $msgtxt{'34'.$language}:

    * $cause.

$msgtxt{'35'.$language} $owner.
_EOF_
  }

 !$deny;
}

#................... UNSUBSCRIBE .....................
sub unsubscribe {

 $cc = "$owner," if ( $cc_on_subscribe =~ /yes/i );

 if ($email) { $cc .= "$email," if ($email ne $from); }
 else { $email = $from; }

 if ($cc) {
   chop $cc;
   $msg .= "Cc: $cc\n";
  }

 if (open LIST, "list".$suffix) {
   $users .= $_ while (<LIST>);
   close LIST;

   $qtemail = $email;
   $qtemail =~ s/\+/\\\+/g;	# Change '+' to '\+' (by Volker)
   if ($users =~ s/(^|\n)$qtemail(>.*)?\n/$1/ig) {
     rename "list".$suffix , "list".$suffix.".bak";
     open LIST, ">list".$suffix;
     &lockf(LIST, 'lock'); $ok = print LIST $users; &lockf(LIST);
     if ($ok) {
       $msg .= $msgtxt{'36'.$language}.$email.$msgtxt{'37'.$language};
       unlink "list".$suffix.".bak"; }
     else {
       rename "list".$suffix.".bak" , "list".$suffix;
       &genAdminReport('unsubscribe');
       $msg .= $msgtxt{'38'.$language}.$email.$msgtxt{'38.1'.$language}."$list\n";
      }
    }
   else {
     $msg .= $msgtxt{'36'.$language}.$email.$msgtxt{'39'.$language};
     $ok = 0;
    }
  }

 $ok;
}

sub genAuthReport {

 my ($authcode) = @_;
 my $msg = <<_EOF_ ;
To: $from
Subject: auth $authcode

$msgtxt{'18'.$language}

	$subject

$msgtxt{'19'.$language}
$me $msgtxt{'20'.$language}

       auth $authcode

$msgtxt{'21'.$language} $auth_valid $msgtxt{'22'.$language}
_EOF_
}

sub genAdminReport {

 my ($rqtype) = @_;

 $adminreport = <<_EOF_ ;
From: Minimalist Manager <$me>
To: $admin
Subject: Error processing
Precedence: High

ERROR:
    Minimalist was unable to process '$rqtype' request on $list for $email.
    There was an error while writing into file "list$suffix".
_EOF_

  open MAIL, "| $sendmail -t -f $me";
  print MAIL "$adminreport\n\n-- \nSincerely, the Minimalist\n";
  close MAIL;
}

# returns user settings in plain/text format
sub txtUserSet {

 my ($userSet, $indicateNO) = @_;
 my $usrmsg;
 my $i = 0;

 if ($userSet) {
   $usrmsg = " :";
   # Permissions
   if ($userSet =~ /\+/) { $usrmsg .= $msgtxt{'43.1'.$language}; $i++; }
   elsif ($userSet =~ /-/) { $usrmsg .= $msgtxt{'43.2'.$language}; $i++; }
   # Suspend
   if ($userSet =~ /!/) { $usrmsg .= ($i++ ? "," : "").$msgtxt{'43.3'.$language} };
   # Maxsize
   if ($userSet =~ /#ms([0-9]+)/) { $usrmsg .= ($i++ ? "," : "").$msgtxt{'43.4'.$language}.$1 };
  }
 elsif ($indicateNO) {
   $usrmsg .= " :".$msgtxt{'43'.$language}; }

 $usrmsg .= "\n";
}

# Changes specified user settings, preserves other 
sub chgUserSet {

 my ($curSet, $pattern, $value) = @_;

 $curSet = '>' if (! $curSet);		# If settings are empty, prepare delimiter

 if ($curSet !~ s/$pattern/$value/g) {	# Change settings
   $curSet .= $value if ($value);	# or add new settings
  }

 $curSet = '' if ($curSet eq '>');	# If setings are empty, remove delimiter

 $curSet;
}

sub chgSettings {

 my ($usermode, $list, $email, $cmdParams) = @_;

 open LIST, "list".$suffix and do {
   while (<LIST>) { chomp ($_); push (@members, lc($_)); }
   close LIST;

   # Quote specials
   $qtemail = $email;
   $qtemail =~ s/\+/\\\+/g;

   for ($i=0; $i < @members; $i++) {
     if ($members[$i] =~ /^($qtemail)(>.*)?$/) {
       $currentSet = $2;
       # Ok, user found
       if ($usermode eq 'reset') {
	 $newSet = &chgUserSet($currentSet, '.*'); }
       elsif ($usermode eq 'usual') {
	 $newSet = &chgUserSet($currentSet, '[-\+]+'); }
       elsif ($usermode eq 'reader') {
	 $newSet = &chgUserSet($currentSet, '[-\+]+', '-'); }
       elsif ($usermode eq 'writer') {
	 $newSet = &chgUserSet($currentSet, '[-\+]+', '+'); }
       elsif ($usermode eq 'suspend') {
	 $newSet = &chgUserSet($currentSet, '!+', '!'); }
       elsif ($usermode eq 'resume') {
	 $newSet = &chgUserSet($currentSet, '!+'); }
       elsif ($usermode eq 'maxsize') {
	 if ($cmdParams+0 == 0) {
	   $newSet = &chgUserSet($currentSet, '(#ms[0-9]+)+'); }
	 else {
	   $newSet = &chgUserSet($currentSet, '(#ms[0-9]+)+', "#ms".($cmdParams+0)); }
	}

       $members[$i] = $email.$newSet;
       $currentSet = '>';	# Indicate, that user found, even if there are no settings
       last;
      }
    }
  };	# open LIST ... do

 if ($currentSet) {		# means, that user found
   foreach (@members) {
     $users .= "$_\n"; }	# prepare plain listing

   rename "list".$suffix, "list".$suffix.".bak";
   open LIST, ">list".$suffix;
   &lockf(LIST, 'lock'); $ok = print LIST $users; &lockf(LIST);
   close LIST;

   if ($ok) {
     $msg .= ($email ne $from ? "Cc: $email\n" : "").
             $msgtxt{'41'.$language}.$email.$msgtxt{'42'.$language}."\U$list\E".
	     &txtUserSet($newSet, 1);
     unlink "list".$suffix.".bak";
    }
   else {	# Write unsuccessfull, report admin
     rename "list".$suffix.".bak", "list".$suffix;
     &genAdminReport('mode');
     $msg .= $msgtxt{'38'.$language}.$email.$msgtxt{'38.1'.$language}."$list\n";
    }
  }
 else { # User not found
   $msg .= $msgtxt{'36'.$language}.$email.$msgtxt{'39'.$language};
  }

 $ok;
}

##########################################################################

#................... READ CONFIG .....................
sub read_config {

my ($fname, $global) = @_;

if (open(CONF, $fname)) {
  while (<CONF>) {

    s/^\s*//gs;
    if($_ =~ /^#/) {

    #............... Global variables .................#

    } elsif (($_ =~ /^directory/i) && $global) {
     ($directive, $directory) = split(/=/, $_, 2);
     $directory =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^password/i && $global) {
     ($directive, $adminpwd) = split(/=/, $_, 2);
     $adminpwd =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^request valid/i && $global) {
     ($directive, $auth_valid) = split(/=/, $_, 2);
     $auth_valid =~ s/$spaces/$1/gs; $auth_valid = lc($auth_valid);

    } elsif (($_ =~ /^blacklist/i) && $global) {
     ($directive, $black) = split(/=/, $_, 2);
     $black =~ s/\s+//g;
     @blacklist = expand_lists(split(':', $black));

    } elsif (($_ =~ /^blocked robots/i) && $global) {			# -VTV-
      # by default no blocking with a string completely replaced here	# -VTV-
      ($directive, $blocked_robots) = split(/=/, $_, 2);		# -VTV-

    } elsif (($_ =~ /^logfile/i) && $global) {
     ($directive, $logfile) = split(/=/, $_, 2);
     $logfile =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^log messages/i && $global) {
     ($directive, $logmessages) = split(/=/, $_, 2);
     $logmessages =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^background/i && $global) {
     ($directive, $background) = split(/=/, $_, 2);
     $background =~ s/$spaces/$1/gs; $background = lc($background);

    # .............. Global and local variables .............. #

    } elsif ($_ =~ /^sendmail/i) {
     ($directive, $sendmail) = split(/=/, $_, 2);
     $sendmail =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^delivery/i) {
     ($directive, $delivery) = split(/=/, $_, 2);
     $delivery =~ s/$spaces/$1/gs;

     if ($delivery =~ s/^alias\s+//i) {
       $delivery_alias = $delivery; $delivery = 'alias';
      }

    } elsif ($_ =~ /^domain/i) {
     ($directive, $domain) = split(/=/, $_, 2);
     $domain =~ s/$spaces/$1/gs;

     # External program?
     if ($domain =~ /^\|/) {
       $domain = eval("`".substr($domain, 1)."`");
       chomp $domain;
      }

    } elsif ($_ =~ /^admin/i) {
     ($directive, $admin) = split(/=/, $_, 2);
     $admin =~ s/$spaces/$1/gs;
     $adminChanged = 1;

    } elsif ($_ =~ /^errors to/i) {
     ($directive, $errors_to) = split(/=/, $_, 2);
     $errors_to =~ s/$spaces/$1/gs; $errors_to = lc($errors_to);

    } elsif ($_ =~ /^security/i) {
     ($directive, $security) = split(/=/, $_, 2);
     $security =~ s/$spaces/$1/gs; $security = lc($security);

    } elsif ($_ =~ /^archive size/i) {	# check before 'archive'
     ($directive, $arcsize) = split(/=/, $_, 2);
     $arcsize =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^archive/i) {
     ($directive, $archive) = split(/=/, $_, 2);
     $archive =~ s/$spaces/$1/gs;

     if ($archive =~ s/^pipe\s+//i) {
       $archpgm = $archive;
       $archive = "pipe"; }
     else {
       $archpgm = 'BUILTIN';
       $archive =~ s/$spaces/$1/gs; $archive = lc($archive);
      }

    } elsif ($_ =~ /^status/i) {
     ($directive, $status) = split(/=/, $_, 2);
     $status =~ s/\s+//g;	# Remove any spaces
     $status = lc($status);

     # Calculate mask for status
     %strel = ("open", $OPEN, "ro", $RO, "closed", $CLOSED, "mandatory", $MANDATORY);
     @starr = split(/,/, $status);
     $status = 0;
     foreach (@starr) { $status += $strel{$_}; }

    } elsif ($_ =~ /^copy to sender/i) {
     ($directive, $copy_sender) = split(/=/, $_, 2);
     $copy_sender =~ s/$spaces/$1/gs; $copy_sender = lc($copy_sender);

    } elsif ($_ =~ /^reply-to list/i) {
     ($directive, $reply_to_list) = split(/=/, $_, 2);
     $reply_to_list =~ s/$spaces/$1/gs; $reply_to_list = lc($reply_to_list);

     # In global config only 'yes' or 'no' allowed
     if ($global && ($reply_to_list ne 'yes')) { $reply_to_list = 'no'; }

    } elsif ($_ =~ /^from/i) {
     ($directive, $outgoing_from) = split(/=/, $_, 2);
     $outgoing_from =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^modify subject/i) {
     ($directive, $modify_subject) = split(/=/, $_, 2);
     $modify_subject =~ s/$spaces/$1/gs; $modify_subject = lc($modify_subject);

    } elsif ($_ =~ /^maxusers/i) {
     ($directive, $maxusers) = split(/=/, $_, 2);
     $maxusers =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^maxrcpts/i) {
     ($directive, $maxrcpts) = split(/=/, $_, 2);
     $maxrcpts =~ s/$spaces/$1/gs;
     
     # Check for bound values
     if ($maxrcpts < 1) { $maxrcpts = 20 }
     elsif ($maxrcpts > 50) { $maxrcpts = 50 }

    } elsif ($_ =~ /^delay/i) {
     ($directive, $delay) = split(/=/, $_, 2);
     $delay =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^maxsize/i) {
     ($directive, $maxsize) = split(/=/, $_, 2);
     $maxsize =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^list information/i) {
     ($directive, $listinfo) = split(/=/, $_, 2);
     $listinfo =~ s/$spaces/$1/gs;

     # Make lowercase if value isn't URL
     $listinfo = lc($listinfo) if ($listinfo =~ /^(yes|no)$/i);

     # In global config only 'yes' or 'no' allowed
     if ($global && ($listinfo ne 'yes')) { $listinfo = 'no'; }

    } elsif ($_ =~ /^strip rrq/i) {
     ($directive, $strip_rrq) = split(/=/, $_, 2);
     $strip_rrq =~ s/$spaces/$1/gs; $strip_rrq = lc($strip_rrq);

    } elsif ($_ =~ /^modify message-id/i) {
     ($directive, $modify_msgid) = split(/=/, $_, 2);
     $modify_msgid =~ s/$spaces/$1/gs; $modify_msgid = lc($modify_msgid);

    } elsif ($_ =~ /^remove resent/i) {
     ($directive, $remove_resent) = split(/=/, $_, 2);
     $remove_resent =~ s/$spaces/$1/gs; $remove_resent = lc($remove_resent);

    } elsif ($_ =~ /^extra header/i) {
     ($directive, $tmp_xtrahdr) = split(/=/, $_, 2);
     $tmp_xtrahdr =~ s/$spaces/$1/gs;
     $xtrahdr .= "$tmp_xtrahdr\n";

    } elsif ($_ =~ /^language/i) {
     ($directive, $language) = split(/=/, $_, 2);
     # Case sensitive, don't do lowercase
     $language =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^cc on subscribe/i) {			# -VTV-
     ($directive, $cc_on_subscribe) = split(/=/, $_, 2);	# -VTV-
     $cc_on_subscribe =~ s/$spaces/$1/gs; $cc_on_subscribe = lc($cc_on_subscribe);

    } elsif ($_ =~ /^charset/i) {
      ($directive, $charset) = split(/=/, $_, 2);
      $charset =~ s/$spaces/$1/gs; $charset = lc($charset);

    #.................... Only local variables ..................#

    } elsif ($_ =~ /^auth/i && !$global) {
     ($directive, $scheme) = split(/=/, $_, 2); $scheme =~ s/$spaces/$1/gs;
     ($auth_scheme, $auth_args) = split(/\s+/, $scheme, 2); $auth_scheme = lc($auth_scheme);

     if ($auth_scheme eq 'mailfrom') {
       $auth_args =~ s/\s+//g;
       @trusted = expand_lists(split(':', $auth_args));
      }
     else { $listpwd =  $auth_args; }

    } elsif ($_ =~ /^list gecos/i && !$global) {
     ($directive, $list_gecos) = split(/=/, $_, 2);
     $list_gecos =~ s/$spaces/$1/gs;

    } elsif ($_ =~ /^to recipient/i && !$global) {
     ($directive, $to_recipient) = split(/=/, $_, 2);
     $to_recipient =~ s/$spaces/$1/gs; $to_recipient = lc($to_recipient);

    }
  }
  close CONF;
 }

 if ( ($auth_scheme eq 'mailfrom') && @trusted ) {
   $verify = 'grep(/^$qfrom$/i, @trusted) || ($userpwd eq $adminpwd)'; }
 else {
   $verify = '($userpwd eq $listpwd) || ($userpwd eq $adminpwd)'; }

 $me = "minimalist\@$domain";

 if ($errors_to eq 'drop') { $envelope_sender = "-f $me"; }
 elsif ($errors_to eq 'admin') { $envelope_sender = "-f $admin"; }
 elsif ($errors_to ne 'sender' && $errors_to ne 'verp') { $envelope_sender = "-f $errors_to"; }
 else { $envelope_sender = ""; }

 $logmessages = 'no' if ($logfile eq 'none');
 $arcsize = 0 if ($archive eq 'no');
 $admin = "postmaster\@$domain" if (! $adminChanged );
 $maxrcpts = 1 if ($errors_to eq 'verp' || $to_recipient eq 'yes');

 chomp $xtrahdr;
 $xtrahdr =~ s/\\a/$admin/ig;
 $xtrahdr =~ s/\\d/$domain/ig;
 $xtrahdr =~ s/\\l/$list/ig;
 $xtrahdr =~ s/\\o/$list-owner\@$domain/ig;
 $xtrahdr =~ s/\\n/\n/ig;
 $xtrahdr =~ s/\\t/\t/ig;
 $xtrahdr =~ s/\\s/ /ig;
}

#..........................................................
sub expand_lists {
 my (@junk) = @_;
 my (@result);

 foreach $s (@junk) {
   if ( $s =~ s/^\@// ) {	# Expand items, starting with '@'
     if (open(IN, $s)) {
       while (<IN>) {
         chomp $_; $result[@result] = $_; }
       close IN;
      }
    }
   elsif ($s ne '') { $result[@result] = $s; }
  }
 @result;
}

#.......... Read file and substitute all macroses .........
sub read_info {
 my ($fname) = @_;
 my $tail;

 if (open(TAIL, $fname)) {
   $tail .= $_ while (<TAIL>);
   close TAIL;

   if ($tail) {
     $tail =~ s/\\a/$admin/ig;
     $tail =~ s/\\d/$domain/ig;
     $tail =~ s/\\l/$list/ig;
     $tail =~ s/\\o/$list-owner\@$domain/ig;
    }
  }

 $tail;
}

#.......... Send ready portion of message ............
sub sendPortion {
 my ($hdr) = $header;

 chop $bcc;
 my ($verp_bcc) = $bcc; $verp_bcc =~ s/\@/=/g;

 $hdr .= "To: $bcc\n" if ($to_recipient eq 'yes');
 $envelope_sender = "-f $list-owner-$verp_bcc\@$domain" if ($errors_to eq 'verp');

 open MAIL, "| $sendmail $envelope_sender $bcc";
 print MAIL $hdr."\n\n".$body;
 close MAIL;
}

#.................... Built-in archiver ..........................
sub archive {

 @date = localtime;
 $year = 1900 + $date[5];
 $month = 1 + $date[4];
 $day = $date[3];

 $path = "archive/";
 mkdir($path, 0755) if (! -d $path);

 @types = ("yearly", "monthly", "daily");
 %rel = ($types[0], $year, $types[1], $month, $types[2], $day);

 foreach $key (@types) {
   $path .= $rel{$key}."./";
   mkdir($path, 0755) if (! -d $path);
   last if ($key eq $archive);
  }

 if (open(NUM, $path."SEQUENCE")) {
   read NUM, $msgnum, 16;
   $msgnum = int($msgnum);
   close NUM;
  }
 else { $msgnum = 0 }

 open ARCHIVE, ">$path".$msgnum;
 print ARCHIVE $header."\n".$body;
 close ARCHIVE;

 open NUM, ">$path"."SEQUENCE";
 print NUM $msgnum+1;
 close NUM;
}

#.................... External archiver ..........................
sub arch_pipe {

 open (ARCHIVE, "| $archpgm");
 print ARCHIVE $header."\n".$body;
 close (ARCHIVE);
}

#.................... Generate authentication code ...............
sub genAuth {

 my ($cmdParams) = @_;
 my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
 my ($authcode) = $mon.$mday.$hour.$min.$sec."-$$";

 mkdir ("$directory/.auth", 0750) if (! -d "$directory/.auth");

 open AUTH, ">$directory/.auth/$authcode";
 print AUTH "$cmd $list$suffix $from $cmdParams\n";
 close AUTH;

 $authcode;
}

#................. Check for authentication code ...............
sub getAuth {

 my ($cmd, $list, $email, $cmdParams);
 my ($authcode) = @_;
 my ($authfile) = "$directory/.auth/$authcode";

 if ($authcode =~ /^[0-9]+\-[0-9]+$/) {
   open AUTH, $authfile and do {
     $authtask = <AUTH>; chomp $authtask;
     close AUTH; unlink $authfile;

     ($cmd, $list, $email, $cmdParams) = split(/\s+/, $authtask);

     if ($list =~ s/^(.*?)(-writers)$/$1/) {	# -writers ?
       $suffix = $2; }

     ($cmd, $list, $email, $cmdParams);
    }
  }
}

#............... Clean old authentication requests .............
sub cleanAuth {

 my $now = time;
 my $dir = "$directory/.auth";
 my $mark = "$dir/.lastclean";

 if (! -f $mark) { open LC, "> $mark"; close LC; return; }
 else {
   my @ftime = stat(_);
   return if ($now - $ftime[9] < $auth_seconds);	# Return if too early
  }

 utime $now, $now, $mark;	# Touch .lastclean
 opendir DIR, $dir;
 while ($entry = readdir DIR) {
   if ($entry !~ /^\./ && -f "$dir/$entry") {
     @ftime = stat(_);
     unlink "$dir/$entry" if ($now - $ftime[9] > $auth_seconds);
    }
  }
 closedir DIR;
}

#............................ Locking .........................
sub lockf {
 my ($FD, $lock) = @_;

 if ($lock) {		# Lock FD
   flock $FD, LOCK_EX;
   seek $FD, 0, 2;
  }
 else {			# Unlock FD and close it
   flock $FD, LOCK_UN;
   close $FD;
  }
}

#......................... Logging activity ....................
sub logCommand {

 my ($command) = @_;

 $command =~ s/\n+/ /g; $command =~ s/\s{2,}/ /g;	# Prepare for logging

 open FILE, ">>$logfile"; &lockf(FILE, 1);
 @ct = localtime(); $gecos = "($gecos)" if ($gecos);

 printf FILE "%s %02d %02d:%02d %d %s\n",
   (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec))[$ct[4]],
   $ct[3], $ct[2], $ct[1], 1900+$ct[5], "$from $gecos: $command";
 &lockf(FILE);
}

#..................... Swap username & domain ...................
sub Invert {
 my $delim = shift (@_);
 my $newdelim = shift (@_);
 my @var = @_;
 my $restdelim = '>';	# And remember about user's specific flags, which are delimited by '>'
 my ($i, $us, $dom, $usdom, $rest) = 0;

 for (; $i < @var; $i++) {
   ($usdom, $rest) = split ($restdelim, $var[$i]);
   ($us, $dom) = split ($delim, $usdom);
   $var[$i] = $dom.$newdelim.$us.($rest ? $restdelim.$rest : "");
  }

 @var;
}

##################################################################
##################################################################
###   i18n of messages - should be fairly easy to understand   ###
##################################################################
##################################################################

sub InitMessages {

##################################################################
###   en = English

#-------------------------------
$msgtxt{'1en'} = <<_EOF_ ;
This is the Minimalist Mailing List Manager.

Commands may be either in subject of message (one command per message)
or in body (one or more commands, one per line). Batched processing starts
when subject either empty or contains command 'body' (without quotes) and
stops when either arrives command 'stop' or 'exit' (without quotes) or
gets 10 incorrect commands.

Supported commands are:

subscribe <list> [<email>] :
    Subscribe user to <list>. If <list> contains suffix '-writers', user
    will be able to write to this <list>, but will not receive messages
    from it.

unsubscribe <list> [<email>] :
    Unsubscribe user from <list>. Can be used with suffix '-writers' (see
    above description for subscribe)

auth <code> :
    Confirm command, used in response to subscription requests in some cases.
    This command isn't standalone, it must be used only in response to a
    request by Minimalist.

mode <list> <email> <mode> :
    Set mode for specified user on specified list. Allowed only for
    administrator. Mode can be (without quotes):
      * 'reader' - read-only access to the list for the user;
      * 'writer' - user can post messages to the list regardless of list's
                   status
      * 'usual' -  clear any two above mentioned modes
      * 'suspend' - suspend user subscription
      * 'resume' - resume previously suspended permission
      * 'maxsize <size>' - set maximum size (in bytes) of messages, which
                           user wants to receive
      * 'reset' - clear all modes for specified user

suspend <list> :
    Stop receiving of messages from specified mailing list

resume <list> :
    Restore receiving of messages from specified mailing list

maxsize <list> <size> :
    Set maximum size (in bytes) of messages, which user wants to receive

which [<email>] :
    Return list of lists to which user is subscribed

info [<list>] :
    Request information about all existing lists or about <list>

who <list> :
    Return the list of users subscribed to <list>

help :
    This message

Note, that commands with <email>, 'who' and 'mode' can only be used by
administrators (users identified in the 'mailfrom' authentication scheme or
who used a correct password - either global or local). Otherwise command will
be ignored. Password must be supplied in any header of message as fragment of
the header in the following format:

{pwd: list_password}

For example:

To: MML Discussion {pwd: password1235} <mml-general\@kiev.sovam.com>

This fragment, of course, will be removed from the header before sending message
to subscribers.
_EOF_

#-------------------------------
$msgtxt{'2en'} = "ERROR:\n\tYou";
$msgtxt{'3en'} = "are not subscribed to this list";
$msgtxt{'3.1en'} = ".\n\nSOLUTION:\n\tSend a message to";
$msgtxt{'4en'} = "with a subject\n\tof 'help' (no quotes) for information about how to subscribe.\n\n".
		 "Your message follows:";
#-------------------------------
$msgtxt{'5en'} = "ERROR:\n\tYou";
$msgtxt{'5.1en'} = "are not allowed to write to this list.\n\nYour message follows:";
#-------------------------------
$msgtxt{'6en'} = "ERROR:\n\tMessage size is larger than maximum allowed (";
$msgtxt{'7en'} = "bytes ).\n\nSOLUTION:\n\tEither send a smaller message or split your message into multiple\n\tsmaller ones.\n\n".
		 "===========================================================================\n".
		 "Your message's header follows:";
#-------------------------------
$msgtxt{'8en'} = "\nERROR:\n\tThere is no authentication request with such code: ";
$msgtxt{'9en'} = "\n\nSOLUTION:\n\tResend your request to Minimalist.\n";

#-------------------------------
$msgtxt{'10en'} = "\nERROR:\n\tYou are not allowed to get subscription of other users.\n".
		  "\nSOLUTION:\n\tNone.";
#-------------------------------
$msgtxt{'11en'} = "\nCurrent subscription of user ";
#-------------------------------
$msgtxt{'12en'} = "\nERROR:\n\tThere is no such list";
$msgtxt{'13en'} = "here.\n\nSOLUTION:\n\tSend a message to";
$msgtxt{'14en'} = "with a subject\n\tof 'info' (no quotes) for a list of available mailing lists.\n";
#-------------------------------
$msgtxt{'15en'} = "\nERROR:\n\tYou aren't allowed to subscribe other people.\n".
		  "\nSOLUTION:\n\tNone.";
#-------------------------------
$msgtxt{'16en'} = "\nERROR:\n\tSorry, this list is closed for you.\n".
		  "\nSOLUTION:\n\tAre you unsure? Please, complain to ";
#-------------------------------
$msgtxt{'17en'} = "\nERROR:\n\tSorry, this list is mandatory for you.\n".
		  "\nSOLUTION:\n\tAre you unsure? Please, complain to ";
#-------------------------------
$msgtxt{'18en'} = "Your request";
$msgtxt{'19en'} = "must be authenticated. To accomplish this, send another request to";
$msgtxt{'20en'} = "(or just press 'Reply' in your mail reader)\nwith the following subject:";
$msgtxt{'21en'} = "This authentication request is valid for the next";
$msgtxt{'22en'} = "hours from now and then\nwill be discarded.\n";
#-------------------------------
$msgtxt{'23en'} = "\nHere is the available information about";
#-------------------------------
$msgtxt{'24en'} = "\nThese are the mailing lists available at";
#-------------------------------
$msgtxt{'25en'} = "\nUsers, subscribed to";
$msgtxt{'25.1en'} = "\nTotal: ";
#-------------------------------
$msgtxt{'26en'} = "\nERROR:\n\tYou are not allowed to get listing of subscribed users.";
#-------------------------------
$msgtxt{'27.0en'} = "Bad syntax or unknown instruction";
$msgtxt{'27en'} = "\nERROR:\n\t".$msgtxt{'27.0en'}.".\n\nSOLUTION:\n\n".$msgtxt{'1en'};
#-------------------------------
$msgtxt{'28en'} = "Sincerely, the Minimalist";
#-------------------------------
$msgtxt{'29en'} = "you already subscribed to";
#-------------------------------
$msgtxt{'30en'} = "there are already the maximum number of subscribers (";
#-------------------------------
$msgtxt{'31en'} = "you have subscribed to";
$msgtxt{'32en'} = "successfully.\n\nPlease note the following:\n";
#-------------------------------
$msgtxt{'33en'} = "you have not subscribed to";
$msgtxt{'34en'} = "due to the following reason";
$msgtxt{'35en'} = "If you have any comments or questions, please, send them to the list\nadministrator";
#-------------------------------
$msgtxt{'36en'} = "\nUser ";
$msgtxt{'37en'} = " has successfully unsubscribed.\n";
#-------------------------------
$msgtxt{'38en'} = "\nInternal error while processing your request; report sent to administrator.".
		  "\nPlease note, that subscription status for ";
$msgtxt{'38.1en'} = " not changed on ";
#-------------------------------
$msgtxt{'39en'} = " is not a registered member of this list.\n";
#-------------------------------
$msgtxt{'40en'} = "\nDear";
#-------------------------------
$msgtxt{'41en'} = "\nSettings for user ";
$msgtxt{'42en'} = " on list ";
$msgtxt{'43en'} = " there are no specific settings";
$msgtxt{'43.1en'} = " posts are allowed";
$msgtxt{'43.2en'} = " posts are not allowed";
$msgtxt{'43.3en'} = " subscription suspended";
$msgtxt{'43.4en'} = " maximum message size is ";
#-------------------------------
$msgtxt{'44en'} = "\nERROR:\n\tYou are not allowed to change settings of other people.\n".
		  "\nSOLUTION:\n\tNone.";

#
# Files with other translations, if available, can be found in
# distribution, in directory languages/ OR on Web, at
# http://www.mml.org.ua/languages/
#

push (@languages, 'ru');

##################################################################
###   ru = Russian

#-------------------------------
$msgtxt{'1ru'} = <<_EOF_ ;
This is the Minimalist Mailing List Manager.

Команды могут быть указаны как в теме письма (одна команда на письмо), так
и в теле письма (одна и более команд, в одной в каждой строке). Обработка
команд в теле письма производится в том случае, если тема письма либо
пустая, либо содержит команду 'body' (без кавычек). Заканчивается обработка
либо в случае достижения команды 'stop' или 'exit' (без кавычек), либо по
получении 10 неправильных команд.

Поддерживаются следующие команды:

subscribe <list> [<email>] :
    подписать пользователя на список <list>. Если список <list> содержит
    суффикс '-writers', пользователь может писать в список <list>, но не
    будет получать сообщения, отправленные в этот список.

unsubscribe <list> [<email>] :
    отписаться от списка <list>. Может быть использован с суффиксом
    '-writers' (описание этой возможности см. выше)

auth <code> :
    подтверждающая команда авторизации. Эта команда никогда не
    используется сама по себе, а только в ответ на запрос менеджера списка
    рассылки.

mode <list> <email> <mode> :
    Установить для указанного подписчика параметры отправки и получения
    сообщений рассылки. Команда разрешена только для администратора
    рассылки.  Параметр 'mode' может принимать следующие значения
    (указывать без кавычек):
      * 'reader' - подписчик не сможет публиковать сообщения в рассылке;
      * 'writer' - подписчик сможет публиковать сообщения в рассылке даже
                   если общая конфигурация не разрешает публикацию;
      * 'usual' - сбросить любую из двух указанных выше настроек. Права
		  подписчика будут определяться общей конфигурацией
		  рассылки.
      * 'suspend' - приостановить получение сообщений пользователем
      * 'resume' - восстановить получение сообщений пользователем
      * 'maxsize <size>' - установить максимальный размер сообщений (в
			   байтах), которые будут отправляться
			   пользователю из указанной рассылки.
      * 'reset' - сбросить все параметры пользователя.
    
suspend <list>:
    приостановить получение сообщений из рассылки

resume <list>:
    восстановить прекращенное ранее командой 'suspend' получение сообщений
    из рассылки

maxsize <list> <size>:
    установить максимальный размер сообщений (в байтах), которые будут
    отправляться пользователю из указанной рассылки.

which [<email>] :
    получить перечень списков рассылки, на которые подписан пользователь

info [<list>] :
    получить дополнительную информацию о существующих списках рассылки или
    о списке <list>

who <list> :
    получить список подписчиков на рассылку <list>

help :
    Сообщение с помощью (это сообщение)

Обратите внимание, что <email> во всех командах и команды 'who' и 'mode'
могут быть использованы только администраторами (пользователями, прошедшими
аутентификацию, установленную директивой auth рассылки или глобальным
паролем). В противном случае команда будет проигнорирована. Пароль должен
быть указан, как фрагмент любого заголовка письма, в таком виде:

{pwd: list_password}

Например:

To: MML Discussion {pwd: password1235} <mml-general\@kiev.sovam.com>

Этот фрагмент будет удален из сообщения перед тем, как сообщение будет
отправлено подписчикам списка рассылки.
_EOF_

#-------------------------------
$msgtxt{'2ru'} = "Ошибка:\n\tВы";
$msgtxt{'3ru'} = "не подписаны на эту рассылку";
$msgtxt{'3.1ru'} = ".\n\nРешение проблемы:\n\tОтправьте сообщение по адресу";
$msgtxt{'4ru'} = "с темой\n\t'help' (без кавычек) для получения информации о том, как подписаться.\n\n".
		 "Далее идет Ваше сообщение:";
#-------------------------------
$msgtxt{'5ru'} = "Ошибка:\n\tВы не можете отправлять письма в данную рассылку.\n\n".
		 "Далее идет Ваше сообщение:";
#-------------------------------
$msgtxt{'6ru'} = "Ошибка:\n\tДлина Вашего сообшения больше максимально допустимой (";
$msgtxt{'7ru'} = "байт).\n\nРешение проблемы:\n\tЛибо сократите Ваше сообщение, либо пошлите его,\n\tразбив на несколько меньших частей.\n\n".
		 "===========================================================================\n".
		 "Далее идет Ваше сообщение:";
#-------------------------------
$msgtxt{'8ru'} = "\nОшибка:\n\tВ нашей базе нет запроса с таким кодом идентификации: ";
$msgtxt{'9ru'} = "\n\nРешение проблемы:\n\tПожалуйста, пошлите ваш запрос еще раз.\n";

#-------------------------------
$msgtxt{'10ru'} = "\nОшибка:\n\tВы не можете просмотреть списки рассылок, на которые подписаны другие пользователи.\n".
		  "\nРешение проблемы:\n\tИзвините, Вы не можете это изменить :)";
#-------------------------------
$msgtxt{'11ru'} = "\nТекущий список подписки пользователя на рассылки ";
#-------------------------------
$msgtxt{'12ru'} = "\nОшибка:\n\tТакого списка рассылки не существует";
$msgtxt{'13ru'} = ".\n\nРешение проблемы:\n\tПошлите сообщение по адресу";
$msgtxt{'14ru'} = "с темой\n\t'info' (без кавычек) для получения списка существующих почтовых рассылок.\n";
#-------------------------------
$msgtxt{'15ru'} = "\nОшибка:\n\tВы не можете в данной рассылке менять статус других пользователей.\n".
		  "\nРешение проблемы:\n\tИзвините, Вы не можете это изменить :)";
#-------------------------------
$msgtxt{'16ru'} = "\nОшибка:\n\tИзвините, вы не можете послать сообщение в этот список рассылки.\n".
		  "\nРешение проблемы:\n\tВы думаете, что это неверно? Сообщите об этом по адресу ";
#-------------------------------
$msgtxt{'17ru'} = "\nОшибка:\n\tИзвините, вы не можете отписаться от этого списка рассылки.\n".
		  "\nРешение проблемы:\n\tВы думаете, что это неверно? Сообщите об этом по адресу ";
#-------------------------------
$msgtxt{'18ru'} = "Ваш запрос";
$msgtxt{'19ru'} = "должен быть авторизирован. Для этого пожалуйста пошлите другой запрос по адресу";
$msgtxt{'20ru'} = "(или просто нажмите кнопку 'Reply' в вашей почтовой программе)\nс таким заголовком:";
$msgtxt{'21ru'} = "Вы можете это сделать в течение";
$msgtxt{'22ru'} = "часов с момента получения этого письма. По прошествии этого срока запрос\nбудет удален.\n";
#-------------------------------
$msgtxt{'23ru'} = "\nНиже приведена вся доступная информация о";
#-------------------------------
$msgtxt{'24ru'} = "\nВ данный момент доступны следующие списки рассылки";
#-------------------------------
$msgtxt{'25ru'} = "\nСписок пользователей, подписанных на";
$msgtxt{'25.1ru'} = "\nВсего пользователей: ";
#-------------------------------
$msgtxt{'26ru'} = "\nОшибка:\n\tВы не можете получить список пользователей, подписанных на данную рассылку.";
#-------------------------------
$msgtxt{'27.0ru'} = "неправильно оформлен запрос или неверная команда";
$msgtxt{'27ru'} = "\nОшибка:\n\t".$msgtxt{'27.0ru'}.".\n\nРешение проблемы:\n\n".$msgtxt{'1ru'};
#-------------------------------
$msgtxt{'28ru'} = "Sincerely, the Minimalist";
#-------------------------------
$msgtxt{'29ru'} = "Вы уже подписаны на группу рассылки";
#-------------------------------
$msgtxt{'30ru'} = "к сожалению, лимит подписчиков на данную рассылку исчерпан (";
#-------------------------------
$msgtxt{'31ru'} = "вы успешно подписались на список";
$msgtxt{'32ru'} = ".\n\nПожалуйста, обратите внимание на следующее:\n";
#-------------------------------
$msgtxt{'33ru'} = "вы не были подписаны на список";
$msgtxt{'34ru'} = "по следующей причине";
$msgtxt{'35ru'} = "Если у вас есть вопросы или предложения, пожалуйста, отправьте их администратору\nсписка рассылки";
#-------------------------------
$msgtxt{'36ru'} = "\nПользователь ";
$msgtxt{'37ru'} = " отписан от рассылки.\n";
#-------------------------------
$msgtxt{'38ru'} = "\nОшибка обработки Вашего запроса; сообщение направлено администратору.".
		  "\nПожалуйста, обратите внимание, что подписка для ";
$msgtxt{'38.1ru'} = " не изменилась в списке рассылки ";
#-------------------------------
$msgtxt{'39ru'} = " не является зарегистрированным подписчиком данного списка рассылки.\n";
#-------------------------------
$msgtxt{'40ru'} = "\nУважаемый(-ая)";
#-------------------------------
$msgtxt{'41ru'} = "\nСпецифические параметры для подписчика ";
$msgtxt{'42ru'} = " в рассылке ";
$msgtxt{'43ru'} = " не установлены";
$msgtxt{'43.1ru'} = " публикация разрешена";
$msgtxt{'43.2ru'} = " публикация не разрешена";
$msgtxt{'43.3ru'} = " подписка приостановлена";
$msgtxt{'43.4ru'} = " максимальный размер сообщения (байт): ";
#-------------------------------
$msgtxt{'44ru'} = "\nОШИБКА:\n\tВам не разрешено менять параметры доступа других подписчиков к рассылке.\n".
		  "\nРЕШЕНИЕ:\n\tОтсутствует.";

}
