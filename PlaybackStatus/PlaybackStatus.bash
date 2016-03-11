#!/bin/bash

# ---------------------------- Helper Functions ---------------------------------------------------
function printScriptUsage
{
	echo "Usage: ./PlaybackStatus.bash {pathToConfigXml | help}"
}

function isFileExistant
{
	if [[ ! -f $1 ]]; then
		echo "File" $1 "was not found."
		exit 1
	fi
}

function readLastCmd
{
	sLastCmd=$(xmlstarlet sel -t -m '//command' -v . <$sMusicCmdInfoPath)
	iLastCmdTimestamp=$(xmlstarlet sel -t -m '//timestamp' -v . <$sMusicCmdInfoPath)
}

function readCurrentInfos
{
	sVolumeLevelSaved=$(xmlstarlet sel -t -m '//volume' -v . <$sPlaybackInfoPath)
	sPlayerStateSaved=$(xmlstarlet sel -t -m '//playerState' -v . <$sPlaybackInfoPath)
}

function checkProcess
{
	sPid=$(cat "$(xmlstarlet sel -t -m '//playbackControlPid' -v . <$sConfigFilePath)")
	sPlaybackProcStatus=$(ps -p $(echo "$sPid"))
	sOmxPlayerStatus=$(pgrep "omxplayer.bin")
}

function getVolumeFromStdOut
{
	echo "$(grep -o "[-\ ]\{1\}[0-9]\{1,3\}.00dB" "$sStdOutFilePath" | tail -1)"
}

function getPauseStatus
{
	echo "$(grep -o 'RESUMED\|PAUSED' "$sStdOutFilePath" | tail -1)"
}

function updatePlayerState
{
	echo "Updating player state to $1"
	sPlayerState="$1"
	xmlstarlet ed --inplace -u '//playerState' -v "$1" "$sPlaybackInfoPath" 
}

function updateVolumeInfo
{
	echo "Updating volume level to $1"
	sVolumeLevel="$1"
	xmlstarlet ed --inplace -u '//volume' -v "$1" "$sPlaybackInfoPath" 
}

# -------------------------------------------------------------------------------------------------

# ------------------------------- Input Check -----------------------------------------------------
if [ "$#" -ne 1 ]; then
    echo "Illegal number of parameters!"
	printScriptUsage
	exit 1
fi

if [ "$1" == "help" ]; then
    echo "File not found!"
	printScriptUsage
	exit 1
fi

if [ ! -f $1 ]; then
    echo "File not found!"
	printScriptUsage
	exit 1
fi
# -------------------------------------------------------------------------------------------------

# --------------------------- Init core variables -------------------------------------------------
sConfigFilePath=$1
sPid=$(cat "$(xmlstarlet sel -t -m '//playbackControlPid' -v . <$sConfigFilePath)")
sPlaybackProcStatus=$(ps -p $(echo "$sPid"))
sOmxPlayerStatus=$(pgrep "omxplayer.bin")

sMusicCmdInfoPath=$(xmlstarlet sel -t -m '//musicCmdInfo' -v . <$sConfigFilePath)
sPlaybackInfoPath=$(xmlstarlet sel -t -m '//playbackInfo' -v . <$sConfigFilePath)

sStdOutFilePath=$(xmlstarlet sel -t -m '//stdOutFile' -v . <$sConfigFilePath)
sStdErrFilePath=$(xmlstarlet sel -t -m '//stdErrFile' -v . <$sConfigFilePath)

sLastCmd=$(xmlstarlet sel -t -m '//command' -v . < $(xmlstarlet sel -t -m '//musicCmdInfo' -v . <$sConfigFilePath))
iLastCmdTimestamp=$(xmlstarlet sel -t -m '//timestamp' -v . < $(xmlstarlet sel -t -m '//musicCmdInfo' -v . <$sConfigFilePath))

fMonitorRateMs=$(xmlstarlet sel -t -m '//monitorRateMs' -v . <$sConfigFilePath)
iCmdTimeoutS=$(xmlstarlet sel -t -m '//cmdTimeoutS' -v . <$sConfigFilePath)

sVolumeLevelSaved=$(xmlstarlet sel -t -m '//volume' -v . <$sPlaybackInfoPath)
sPlayerStateSaved=$(xmlstarlet sel -t -m '//playerState' -v . <$sPlaybackInfoPath)

sPLAYER_RUNNING="RUNNING"
sPLAYER_PAUSED="PAUSED"
sPLAYER_RESUMED="RESUMED"
sPLAYER_STOPED="STOPED"
sPLAYER_INACTIVE="INACTIVE"
sPLAYER_ERR_CMD_TIMEOUT="ERR_CMD_TIMEOUT"
sPLAYER_ERR_FALSE_CMD="ERR_FALSE_CMD"

sVolumeLevel="_"
sPlayerState="_"
sCurVolumeNoPlayback="-80.00dB" 
# -------------------------------------------------------------------------------------------------

# ------------------------------- Check FilePaths -------------------------------------------------
isFileExistant $sMusicCmdInfoPath
isFileExistant $sPlaybackInfoPath
isFileExistant $sStdOutFilePath
isFileExistant $sStdErrFilePath
# -------------------------------------------------------------------------------------------------

# --------------------------------- Init Playback Status ------------------------------------------
updatePlayerState "$sPLAYER_INACTIVE"
updateVolumeInfo "$sCurVolumeNoPlayback"
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# --------------------------------- Main Endless Execution Loop -----------------------------------
# -------------------------------------------------------------------------------------------------
echo "Starting Player Status Daemon"
while [ 1 ]; do
	checkProcess
	if [[ "$sPlaybackProcStatus" == *"PlaybackControl"* ]] # Checking if music processes are alive
	then
		if [ -n "$sOmxPlayerStatus" ]
		then
			readLastCmd
			if [ $((iTimestamp - iLastCmdTimestamp)) -lt $iCmdTimeoutS ] 	# Updating playback status info
			then
				if [ "$sLastCmd" == "START" ] || [ "$sLastCmd" == "NEXT_TRACK" ] || [ "$sLastCmd" == "INCREASE_VOLUME" ] || [ "$sLastCmd" == "DECREASE_VOLUME" ] || [ "$sLastCmd" == "FAST_FORWARD" ] || [ "$sLastCmd" == "FAST_BACKWARD" ]
				then
					if [ "$sPlayerState" != "$sPLAYER_RUNNING" ]
					then
						updatePlayerState "$sPLAYER_RUNNING"
					fi
				elif [ "$sLastCmd" == "PAUSE" ]
				then
					if [ "$sPlayerState" != "$(getPauseStatus)" ]
					then 
						updatePlayerState "$(getPauseStatus)" 
					fi
				elif [ "$sLastCmd" == "STOP" ]
				then
					if [ "$sPlayerState" != "$sPLAYER_STOPED" ]
					then 
						updatePlayerState "$sPLAYER_STOPED"
					fi
				else
					if [ "$sPlayerState" != "$sPLAYER_ERR_FALSE_CMD" ]
					then 
						updatePlayerState "$sPLAYER_ERR_FALSE_CMD"
					fi
				fi
			else
				#Command timeout Error
				if ["$sPlayerState" != "$sPLAYER_ERR_CMD_TIMEOUT"]; then 
					updatePlayerState "$sPLAYER_ERR_CMD_TIMEOUT"
				fi
			fi
				#Grep the Playback StdOut in search of the current volume and update xml
				sCurVolume="$(getVolumeFromStdOut)" 
				if [ "$sVolumeLevel" != "$sCurVolume" ]
				then
					updateVolumeInfo "$sCurVolume"
				fi
			fi
	else
		#processes are not running set the current volume to -80.00dB and update xml
		if [ "$sVolumeLevel" != "$sCurVolumeNoPlayback" ]
		then
			updateVolumeInfo "$sCurVolumeNoPlayback"
		fi
				
		#processes are not running set state as inactive
		if [ "$sPlayerState" != "$sPLAYER_INACTIVE" ]
		then 
			updatePlayerState "$sPLAYER_INACTIVE"
		fi
	fi

	sleep "$fMonitorRateMs"
done


# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------




# ------------------------ Saving Music Playback Status and Volume --------------------------------
# read stdOut.log, read lastMusicCmd.info
# parse information
# save to config


# -------------------------------------------------------------------------------------------------