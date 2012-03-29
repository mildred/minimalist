#!/usr/bin/perl
#
# This tool has written by Volker Tanger <volker.tanger@wyae.de>. Here is
# short explanation from author: "To ease conversion (from one software to
# another) for the users I wrote a small program to catch control mails sent
# to MAILLIST-request@... which many maillist programs use. The proper
# (complete) alias entry for a mailing list then looks like:
#
#       test:           "|/usr/local/sbin/minimalist.pl test"
#       test-request:   "|/usr/local/sbin/minimalist_request.pl test"
#       test-owner:     root

$mailprog = '/usr/lib/sendmail';
$mailfrom = 'minimalist@wyae.de';

####################################################################
# >>>>>>>>>>>>>>>>>>>>>>>>> START HERE <<<<<<<<<<<<<<<<<<<<<<<<<<< #
####################################################################

$list = $ARGV[0];

while (<STDIN>) {
  s/\r//g;		# Remove Windooze's \r, it is safe to do this
  s/\n//g;		# Remove \n it is safe to do this
  if ( m/^From: /i ) { $fromline = $_; }
  if ( m/^Reply-To: /i ) { $replytoline = $_; }
  if ( m/^Subject: /i ) { $subjectline = $_; }
}

($dummy,$from) = split(/</,$fromline,2);
($from,$dummy) = split(/>/,$from,2);

($dummy,$reply) = split(/</,$replytoline,2);
($reply,$dummy) = split(/>/,$reply,2);

($dummy,$subject) = split(/: /,$subjectline,2);


$mailto = ( $reply eq '' ? $from : $reply );



####################################################################

$headmsg = <<_EOF_ ;
This is an assistant program to the Minimalist Mailing List Manager.

The old mailing list manager used to work with a different
(un)subscription method which you just called.

_EOF_

####################################################################

$helpmsg = <<_EOF_ ;


Commands (e.g. subscribing or unsubscribing) shall be sent to
the MiniMaList server at $minimalist 

All commands MUST APPEAR IN THE SUBJECT of mail messages.

Supported commands are:

subscribe <list> [<email>] :
    subscribe user to <list>. If <list> contains suffix '-writers', user
    will be able to write to this <list>, but will not receive messages
    from it.

unsubscribe <list> [<email>] :
    unsubscribe user from <list>. Can be used with suffix '-writers' (see
    above description for subscribe)

auth <code> :
    confirm command, which need to be confirmed. This command isnt
    standalone, it must be used only by Minimalists request.

which [<email>] :
    get list of lists, to which user subscribed

info [<list>] :
    gives you information about existing lists or about <list>

who <list> :
    gives you the list of users subscribed to <list>

help :
    This message

Note, that <email> in all commands and 'who' command can be used only by
administrators.


_EOF_

####################################################################

if ( "$subject" =~ m/unsubscribe/i ) {
    $msg = "You probably should use the subject \"unsubscribe $list\"\nSimply replying to this mail should do the trick, too.";
    $subj = "unsubscribe $list";
} elsif ( "$subject" =~ m/subscribe/i ) {
    $msg = "You probably should use the subject \"subscribe $list\"\nSimply replying to this mail should do the trick, too.";
    $subj = "subscribe $list";
} elsif ( "$subject" =~ m/archive/i ) {
    $msg = "Archive retrieval is not supported via email.";
    $subj = "Mailing List program changed";
} else {
}

####################################################################
# print  "From:  	 $from\n";
# print  "ReplyTo: $reply\n";
# print  "Subject: $subject\n";

open (MAIL, "|$mailprog $mailto");
print MAIL ("From: $mailfrom\n");
print MAIL ("Subject: $subj\n\n");
print MAIL ("$headmsg  \n");
print MAIL ("--------------------------------------------------------\n");
print MAIL ("$msg  \n");
print MAIL ("--------------------------------------------------------\n");
print MAIL ("$helpmsg  \n");
print MAIL ("  \n");
close (MAIL);
