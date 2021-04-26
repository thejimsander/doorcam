#!/usr/bin/perl

$DEBUG = `tty` =~ /^\/dev/ ? 1 : 0;

chomp($HOSTNAME = `hostname`);

# set the TZ so server clock can stay on UTC, but we get localized times for the graph
$ENV{'TZ'}="/usr/share/zoneinfo/US/Eastern";

# define the listening port of the report server based on privilege the program is started with
$PRIV_PORT = 80;
$NONPRIV_PORT = 8888;
$LOCAL_PORT = ($< == 0) ? $PRIV_PORT : $NONPRIV_PORT;

use HTTP::Daemon;
use HTTP::Status;
use POSIX;
use CGI;
$q = new CGI;

# we want defunct child processes to just go away
$SIG{CHLD} = 'IGNORE';

# start the daemon – before we drop privileges, since we may be running on a low port
$d = HTTP::Daemon->new(
	LocalPort=>$LOCAL_PORT,
	ProductTokens=>"Neutron : $VERSION_ID"
) || die "Daemon socket creation failed : '$!'";

#define the string – used in html links
$addr = "http://$HOSTNAME.local" . ($LOCAL_PORT == $PRIV_PORT ? '' : ":$LOCAL_PORT");
print "Please contact me at: <URL:  $addr  >\n" if($DEBUG);

# if we're running as root, and LOCAL_USER is defined, drop privileges to make this a safer service
if($< == 0 and $> == 0 and $LOCAL_USER){
	$uid   = getpwnam($LOCAL_USER);

	if($uid > 0){
		$< = $> = $uid;
		print "Switched process identity to : ".`id` if($DEBUG);
	}
	else{
		die "Failed to find user ID for LOCAL_USER = '$LOCAL_USER'\n" if($DEBUG);
	}
}

# wait for a connection
while (my $cnxn = $d->accept) {

	# fork here : parent will return to wait for new connection
	next unless ! fork();

	# child will process the connection
	$c++;
	print "New connection: $c\n" if($DEBUG);
	while (my $req = $cnxn->get_request) {
		$i++;
		print "New request $i\n" if($DEBUG);

		# if it's not GET it's crap!
		if($req->method ne 'GET'){
			print "ERROR: ".$req->method."\n" if($DEBUG);

			$cnxn->send_error(RC_FORBIDDEN);
		}
		else{

			# convert the rest of the url into "parameters" blindly
			%url = ();
			for (split/\//,$req->uri->path){
				($l,$r)=split/=/;
				next unless ($l); # skip blanks, but keep 'g'
				$url{$l}=$r;
				print "  > $l -> $url{$l}\n" if($DEBUG);
			}

			# set defaults
			$width=int($q->{'width'});
			$width||=1920;

			$height=int($q->{'height'});
			$height||=1080;
			
			$delay=int($q->{'delay'});
			$delay||=100;

			# Exposure Mode
			# off,auto,night,nightpreview,backlight,spotlight,sports,snow,beach,verylong,fixedfps,antishake,fireworks
			$ex=$q->{'ex'};
			$ex||='auto';
			
			# Auto White Balance Mode
			# off,auto,sun,cloud,shade,tungsten,fluorescent,incandescent,flash,horizon,greyworld
			$awb=$q->{'awb'};
			$awb||='auto';

			# Metering Mode
			# average,spot,backlit,matrix
			$mm=$q->{'mm'};
			$mm||='matrix';
			
			# Dynamic Range Compression
			# off,low,med,high
			$drc = $q->{'drc'};
			$drc||='off';
			
			$rot=int($q->{'rot'});
			$rot||=0;

			$ss=int($q->{'ss'});
			$ss||=10000;
			
			
			if(exists $url{'g'}){
				# command-line to produce the image we're about to serve out
				$cmd = "raspistill -t $delay -ss $ss -ex $ex -awb $awb -mm $mm -drc $drc -rot $rot -w $width -h $height -o - ";
			
				# do it!
				print "$c / $i\t$cmd\n" if($DEBUG);
				$imgdata = `$cmd`;

				# send the image back to the client
				$cnxn->send_response(
					HTTP::Response->new(
						RC_OK,
						undef,
						[
							'Content-Type' => "image/png",
							'Cache-Control' => 'no-store, no-cache, must-revalidate, post-check=0, pre-check=0',
							'Pragma' => 'no-cache'
						],
						$imgdata
					)
				);
			}
			else{

				$menu .= $q->popup_menu(
					-name    => 'width',
					-values  => [1920, 1280, 1024, 640],
					-default => $width
				);

				$menu .= $q->popup_menu(
					-name    => 'height',
					-values  => [1080, 800, 600, 480],
					-default => $height
				);
	
				$menu .= $q->popup_menu(
					-name    => 'delay',
					-values  => [80, 100, 200, 400],
					-default => $delay
				);
	
				$menu .= $q->popup_menu(
					-name    => 'rot',
					-values  => [0, 90, 180, 270],
					-default => $rot
				);
	
				$menu .= $q->popup_menu(
					-name    => 'ex',
					-values  => ['off','auto','night','nightpreview','backlight','spotlight','sports','snow','beach','verylong','fixedfps','antishake','fireworks'],
					-default => $ex
				);
				$menu .= $q->popup_menu(
					-name    => 'awb',
					-values  => ['off','auto','sun','cloud','shade','tungsten','fluorescent','incandescent','flash','horizon','greyworld'],
					-default => $awb
				);    

				$menu .= $q->popup_menu(
					-name    => 'mm',
					-values  => ['average','spot','backlit','matrix'],
					-default => $mm
				);

				$menu .= $q->popup_menu(
					-name    => 'drc',
					-values  => ['off','low','med','high'],
					-default => $drc
				);
	
				$menu .= $q->popup_menu(
					-name    => 'ss',
					-values  => [10000000, 1000000, 100000, 50000, 10000, 1000],
					-default => $ss
				);    

				$menu .= $q->submit(
					-value => 'Refresh'
				);

				# CSS-formatted strings of the image size
				$widthpx = $width."px";
				$heightpx = $height."px";
				
				$html = <<"EOF";
<html>
<head>
	<link rel="shortcut icon" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAAXNSR0IArs4c6QAAAERlWElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAEKADAAQAAAABAAAAEAAAAAA0VXHyAAAA5klEQVQ4EWPs6OioY2BgqAZiNiAmBfwCKm5lAhLkaAZZBLKwGmQAqTaDNMMAG8gAigALum5Xhg1AJ/1EFwbzvzLwMhxg8EKRw3DBawZJBnWGKwx/GZgZXjJIgzETwz8GZYabDG8YxFE0gzgYBlxgMGf4w8DKcIdBk+EMgw0YP2BQZfjBwAE01piwARgqCAhguICAegxp+hjwE+h/HobPDEYMx4lzwSkGW4b3DKJwxfcZ1BguMpgxiDC8gIvBGBjpACRxgsERJg+mfwNTxl4GXxQxGIcqYQDKVeSCXyAXtAIxOYaAszMAy94piUc+GLIAAAAASUVORK5CYII=" />
	<title>Camera Controls</title>
	<style>
		body {
			background-color: gray;
			color: black;
		}
		body a { 
			text-decoration: none !important;
			color: red;
		}
		
		.imgbox {
			width: $widthpx;
			height: $heightpx;
		}
	</style>
</head>
<body>
<div class="imgbox"><img src="/g//delay=$delay/ss=$ss/ex=$ex/awb=$awb/mm=$mm/drc=$drc/rot=$rot/width=$width/height=$height/"></div>
<div>
<hr>
<form>$menu</form>
<hr>
</div>
</body>
</html>
EOF

				# send something back to the client
				$cnxn->send_response(
					HTTP::Response->new(
						RC_OK,
						undef,
						[
							'Content-Type' => "text/html"
						],
						$html
					)
				);
			}
		}
		print "Request done! ($i)\n" if($DEBUG);
	}

	print "Connection done! ($c)\n" if($DEBUG);
	$cnxn->close;
	undef($cnxn);

	# no hanging chads
	exit;
}

