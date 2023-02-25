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
use MIME::Base64;
use CGI;
#use Data::Dumper;

# we want defunct child processes to just go away
$SIG{CHLD} = 'IGNORE';

# start the daemon – before we drop privileges, since we may be running on a low port
$d = HTTP::Daemon->new(
	LocalPort=>$LOCAL_PORT,
	ProductTokens=>"Neutron : $VERSION_ID"
) || die "Daemon socket creation failed : '$!'";

#define the string – used in html links
$addr = "http://$HOSTNAME.local" . ($LOCAL_PORT == $PRIV_PORT ? '' : ":$LOCAL_PORT");
print "Please contact me at: < URL :  $addr >\n" if($DEBUG);

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
			$the_uri = $req->uri;
			$the_uri =~ s/^\/\?//;
			
			$IN = new CGI ($the_uri);	

			# set defaults
			$width=int($IN->param('width'));
			$width||=1920;

			$height=int($IN->param('height'));
			$height||=1080;
			
			$delay=int($IN->param('delay'));
			$delay||=100;

			# Exposure Mode
			# off,auto,night,nightpreview,backlight,spotlight,sports,snow,beach,verylong,fixedfps,antishake,fireworks
			$ex=$IN->param('ex');
			$ex||='auto';
			
			# Auto White Balance Mode
			# off,auto,sun,cloud,shade,tungsten,fluorescent,incandescent,flash,horizon,greyworld
			$awb=$IN->param('awb');
			$awb||='auto';

			# Metering Mode
			# average,spot,backlit,matrix
			$mm=$IN->param('mm');
			$mm||='matrix';
			
			# Dynamic Range Compression
			# off,low,med,high
			$drc = $IN->param('drc');
			$drc||='off';
			
			$rot=int($IN->param('rot'));
			$rot||=0;

			$ss=int($IN->param('ss'));
			$ss||=10000;
			
			$refresh=int($IN->param('refresh'));
			$refresh||=300;
			
			# command-line to produce the image we're about to serve out
			$cmd = "raspistill -t $delay -ss $ss -ex $ex -awb $awb -mm $mm -drc $drc -rot $rot -w $width -h $height -o - ";
		
			# do it!
			print "$c / $i\t$cmd\n" if($DEBUG);
			$imgdata = encode_base64(`$cmd`);
			
			$menu ='';
			
			$menu .= $IN->popup_menu(
				-name    => 'width',
				-values  => [1920, 1280, 1024, 640],
				-default => $width
			);

			$menu .= "&nbsp;X&nbsp;" . $IN->popup_menu(
				-name    => 'height',
				-values  => [1080, 800, 600, 480],
				-default => $height
			);

			#$menu .= "Delay:" . $IN->popup_menu(
			#	-name    => 'delay',
			#	-values  => [80, 100, 200, 400],
			#	-default => $delay
			#);

			$menu .= "Rot:" . $IN->popup_menu(
				-name    => 'rot',
				-values  => [0, 90, 180, 270],
				#-labels  => {0 => "0&deg;", 90 => "90&deg;", 180 => '180&deg;', 270 => '270&deg;'},
				-default => $rot
			);

			$menu .= "Exp:" . $IN->popup_menu(
				-name    => 'ex',
				-values  => ['off','auto','night','nightpreview','backlight','spotlight','sports','snow','beach','verylong','fixedfps','antishake','fireworks'],
				-default => $ex
			);
			$menu .= "WB:" . $IN->popup_menu(
				-name    => 'awb',
				-values  => ['off','auto','sun','cloud','shade','tungsten','fluorescent','incandescent','flash','horizon','greyworld'],
				-default => $awb
			);    

			$menu .= "Mode:" . $IN->popup_menu(
				-name    => 'mm',
				-values  => ['average','spot','backlit','matrix'],
				-default => $mm
			);

			$menu .= "DRC:" . $IN->popup_menu(
				-name    => 'drc',
				-values  => ['off','low','med','high'],
				-default => $drc
			);

			$menu .= "Shut:" . $IN->popup_menu(
				-name    => 'ss',
				-values  => [10000000, 1000000, 500000, 100000, 33333, 16666, 10000, 2000, 1000],
				-labels  => {10000000 => '10s', 1000000 => '1s', 500000 => '1/2s', 100000 => '1/10s', 33333 => '1/30s', 16666 => '1/60s', 10000 => '1/100s', 2000 => '1/500s', 1000 => '1/1000s'},
				-default => $ss
			);    

			$menu .= "Ref:" . $IN->popup_menu(
				-name    => 'refresh',
				-values  => [300, 60, 30, 15, 5, 1],
				-labels  => {300 => '5m', 60 => '1m', 30 => '30s', 15 => '15s', 5 => '5s', 1 => '1s'},
				-default => $refresh
			); 
			
			$menu .= $IN->submit(
				-value => 'Reload'
			);

			# CSS-formatted strings of the image size
			$widthpx = $width."px";
			$heightpx = $height."px";
			$form_url = $IN->self_url;

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
<div class='imgbox'><img src='data:image/gif;base64, $imgdata'></div>
<div>
<form action='$addr' method='GET'>$menu</form>
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
						'Content-Type' => "text/html",
						'Refresh' => "$refresh"
					],
					$html
				)
			);
		}
		print "Request done! ($i)\n" if($DEBUG);
	}

	print "Connection done! ($c)\n" if($DEBUG);
	$cnxn->close;
	undef($cnxn);

	# no hanging chads
	exit;
}

