#!/bin/bash

# ---------------------------------- Functions ---------------------------------------------------
function printScriptUsage
{
	echo "Usage: ./RaspiPlayer.bash [option] <parameter>"
	echo "[increaseVolume | +] - increase volume level by 3 dB"
	echo "[decreaseVolume | -] - decrease volume level by 3 dB"
	echo "[setMusicPath] <musicPath> - specify the music directory or single file"
	echo "[setMusicFileOffset] <musicFileName> - specify the file offset within a playlist"
	echo "[setSavedPlaylist] <playlistName> - select saved playlist by name, updates the MusicPath"
	echo "[savePlaylistLocation] <playlistName> <playlistPath> - add a music location"
	echo "[start] -  starts single file or playlist playback"
	echo "[stop] - stop playback (if active)"
	echo "[pause | resume] - pause playback (if active)"
	#echo "[previousTrack] - start previous track"
	echo "[nextTrack] - start next track"
	echo "[repeat]  <0 | 1> - repeat playback  [default off]"
	echo "[shuffle] <0 | 1> - shuffle playlist [default off]"
	echo "[resetSettings] -  changing configuration to default values"
}

function isPathValid
{
	if [ -f $1 ] || [ -d $1 ]; then
		#0 - true
		echo "0" 
	else
		#1 - false
		echo "1"
	fi
}

function saveMusicFileOffset
{
	xmlstarlet ed --inplace -u '//firstTrack' -v "$1" "$sConfigFilePath"
}

function saveMusicPath
{
	xmlstarlet ed --inplace -u '//musicLocation' -v "$1" "$sConfigFilePath"
}

function setRepeat
{
	sNewRepeatValue=$(($(xmlstarlet sel -t -m '//repeat' -v . <$sConfigFilePath)^1))
	xmlstarlet ed --inplace -u '//repeat' -v "$sNewRepeatValue" "$sConfigFilePath"
}

function setShuffle
{
	sNewShuffleValue=$(($(xmlstarlet sel -t -m '//shuffle' -v . <$sConfigFilePath)^1))
	xmlstarlet ed --inplace -u '//shuffle' -v "$sNewShuffleValue" "$sConfigFilePath"
}

function resetSettingsToDefaults
{
	xmlstarlet ed --inplace -u '//musicLocation' -v "/home/pi/SMB_PUB/Music/5_PolskiePrzeboje" "$sConfigFilePath"
	#xmlstarlet ed --inplace -u '//firstTrack' -v "" "$sConfigFilePath"
	#xmlstarlet ed --inplace -u '//shuffle' -v "0" "$sConfigFilePath"
	#xmlstarlet ed --inplace -u '//repeat' -v "0" "$sConfigFilePath"
	
	#echo "" > $sStdOutFilePath
	#echo "" > $sStdErrFilePath
}

function startPlaybackControl
{
	if [[ "$sPlaybackProcStatus" == *"PlaybackControl"* ]] && [ -n "$sOmxPlayerStatus" ]
	then
		echo "StarCmd: Playback is already running"
	else
		echo "Starting playback Control"
		nohup "$sPlaybackControlPath" "$sConfigFilePath" > "$sStdOutFilePath" 2> "$sStdErrFilePath" & echo $! > "$sPidPath"
		#sendStartCmd
	fi
}

function stopPlaybackControl
{
	if [[ "$sPlaybackProcStatus" == *"PlaybackControl"* ]] && [ -n "$sOmxPlayerStatus" ]
	then
		kill -9 $(echo "$sPid")
		sendStopCmd
	else
		echo "StopCmd: Playback is already inactive"
	fi
}

function sendStartCmd
{
	xmlstarlet ed --inplace -u '//command' -v "START" "$sMusicCmdInfoPath"
	writeTimestamp
}

function sendPauseCmd
{
	nohup echo -n p > "$sPipelinePath" 2>/dev/null
	xmlstarlet ed --inplace -u '//command' -v "PAUSE" "$sMusicCmdInfoPath"
	writeTimestamp
}

function sendStopCmd
{
	killall omxplayer.bin
	xmlstarlet ed --inplace -u '//command' -v "STOP" "$sMusicCmdInfoPath"
	#writeTimestamp
}

function sendNextTrackCmd
{
	nohup echo -n q > "$sPipelinePath" 2>/dev/null
	xmlstarlet ed --inplace -u '//command' -v 'NEXT_TRACK' "$sMusicCmdInfoPath"
	writeTimestamp
}

function sendIncreaseVolumeCmd
{
	nohup echo -n + > "$sPipelinePath" 2>/dev/null
	xmlstarlet ed --inplace -u '//command' -v 'INCREASE_VOLUME' "$sMusicCmdInfoPath"
	writeTimestamp
}

function sendDecreaseVolumeCmd
{
	nohup echo -n - > "$sPipelinePath" 2>/dev/null
	xmlstarlet ed --inplace -u '//command' -v 'DECREASE_VOLUME' "$sMusicCmdInfoPath"
	writeTimestamp
}

function sendFastForward
{
	nohup echo -n $'\x1b\x5b\x43' > "$sPipelinePath" 2>/dev/null
	echo -n $'\x1b\x5b\x44'
	xmlstarlet ed --inplace -u '//command' -v "FAST_FORWARD" "$sMusicCmdInfoPath"
	#writeTimestamp
}

function sendFastBackward
{
	nohup echo -n $'\x1b\x5b\x44' > "$sPipelinePath" 2>/dev/null
	xmlstarlet ed --inplace -u '//command' -v "FAST_BACKWARD" "$sMusicCmdInfoPath"
	#writeTimestamp
}

function writeTimestamp
{
	sTimestamp=$(date +%s)
	xmlstarlet ed --inplace -u '//timestamp' -v "$sTimestamp" "$sMusicCmdInfoPath"
	xmlstarlet ed --inplace -u '//sender' -v 'RaspiPlayer' "$sMusicCmdInfoPath"
}

function updateMusicPathBySavedName
{
	echo "$1"
	sMusicPathNode=$(xmlstarlet sel -t -m "/configuration/MusicLocationCollection/MusicLocation[Name='$1']" -v Path <$sConfigFilePath)
	if [ ! -z "$sMusicPathNode" ]; then
		sResult="$(echo "$(isPathValid "$sMusicPathNode")")"
		if [ "$sResult" == "0" ]; then
			saveMusicPath $sMusicPathNode
			echo "Set the following music path:"
			echo "$sMusicPathNode"
		else
			echo "The music location was not found."
		fi
	else
		echo "The plalylist name was not found."
	fi
}

function updatePlaylistCollection
{
	if [ ! -z "$1" ]; then
			sPathCheck="$(echo "$(isPathValid "$2")")"
		if [ "$sPathCheck" == "0" ]; then
				xmlstarlet ed --inplace --subnode "/configuration/MusicLocationCollection" --type elem -n "MusicLocation" -v "" "$sConfigFilePath"
				xmlstarlet ed --inplace  --subnode "/configuration/MusicLocationCollection/MusicLocation[not(@id)]" --type elem -n "Name" -v "$1" "$sConfigFilePath"
				xmlstarlet ed --inplace  --subnode "/configuration/MusicLocationCollection/MusicLocation[not(@id)]" --type elem -n "Path" -v "$2" "$sConfigFilePath"
				xmlstarlet ed --inplace  --append "/configuration/MusicLocationCollection/MusicLocation[not(@id)]" --type attr -n "id" -v "0" "$sConfigFilePath"
		else
			echo "The music location was not found."
		fi
	else
		echo "The name is invalid"
	fi
}
# -------------------------------------------------------------------------------------------------

# --------------------------- Init core variables -------------------------------------------------
sConfigFilePath=$(echo $(dirname "$0"))"/config.xml"
sPidPath=$(xmlstarlet sel -t -m '//playbackControlPid' -v . <$sConfigFilePath)
sPid=$(cat "$(xmlstarlet sel -t -m '//playbackControlPid' -v . <$sConfigFilePath)")
sPlaybackProcStatus=$(ps -p $(echo "$sPid"))

sOmxPlayerStatus=$(pgrep "omxplayer.bin")
sPipelinePath=$(xmlstarlet sel -t -m '//ctrlPipelineDir' -v . <$sConfigFilePath)

sRaspiDir=$(xmlstarlet sel -t -m '//raspiPlayerDir' -v . <$sConfigFilePath)
sPlaybackControlPath="$sRaspiDir/PlaybackControl/PlaybackControl.bash"

sStdOutFilePath=$(xmlstarlet sel -t -m '//stdOutFile' -v . <$sConfigFilePath)
sStdErrFilePath=$(xmlstarlet sel -t -m '//stdErrFile' -v . <$sConfigFilePath)

sMusicCmdInfoPath=$(xmlstarlet sel -t -m '//musicCmdInfo' -v . <$sConfigFilePath)
sPlaybackInfoPath=$(xmlstarlet sel -t -m '//playbackInfo' -v . <$sConfigFilePath)
# -------------------------------------------------------------------------------------------------

# ------------------------------- Processing input arguments --------------------------------------
if [ "$#" -eq 0 ]; then
    echo "No parameters were specified!"
	printScriptUsage
	exit 1
fi

while :
do
    case "$1" in
	  increaseVolume | +)
	  sendIncreaseVolumeCmd
	  shift
	  break
	  ;;
	  increaseVolume | -)
	  sendDecreaseVolumeCmd
	  shift
	  break
	  ;;
	  setMusicPath)
	  saveMusicPath $2
	  shift 2
	  break
	  ;;
	  setMusicFileOffset)
	  saveMusicFileOffset $2
	  shift 2
	  break
	  ;;
	  start)
	  startPlaybackControl
	  shift
	  break
	  ;;
	  stop)
	  stopPlaybackControl
	  shift
	  break
	  ;;
	  pause | resume)
	  sendPauseCmd
	  shift
	  break
	  ;;
	  nextTrack | next)
	  sendNextTrackCmd
	  shift
	  break
	  ;;
	  repeat)
	  setRepeat
	  shift
	  break
	  ;;
	  shuffle)
	  setShuffle
	  shift
	  break
	  ;;
	  fastForward)
	  sendFastForward
	  shift
	  break
	  ;;
	  fastBackward)
	  sendFastBackward
	  shift
	  break
	  ;;
	  setSavedPlaylist)
	  updateMusicPathBySavedName "$2"
	  shift 2
	  break
	  ;;
	  savePlaylistLocation)
	  updatePlaylistCollection $2 $3
	  shift 3
	  break
	  ;;
	  resetSettings)
	  resetSettingsToDefaults
	  shift
	  break
	  ;;
      -h | --help)
	  printScriptUsage
	  exit 0
	  ;;
      --) # End of all options
	  shift
	  break
	  ;;
      -*)
	  echo "Error: Unknown option: $1" >&2
	  printScriptUsage
	  exit 1
	  ;;
      *)  # No more options
	  printScriptUsage
	  exit 1
	  ;;
    esac
done
# -------------------------------------------------------------------------------------------------