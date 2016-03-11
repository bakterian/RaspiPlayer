#!/bin/bash

#---------------------------- Helper Functions ---------------------------------------------------

function printScriptUsage
{
	echo "Usage: ./PlaybackControl.bash {pathToConfigXml | help}"
}

function isFileExistant
{
	if [[ ! -f $1 ]]; then
		echo "File" $1 "was not found."
		exit 1
	fi
}

function saveFileName
{
	echo "$1" > $sTrackInfoFilePath #insert to file
	sForcedFirstTrack="$1"
}

function saveVolumeSetting
{
	#append to StdOut >>
	echo "Current Volume: 0.00dB"
}

function sendStarCmd
{
	#send play command and forget process, ignore stdOut and stdErr
	nohup echo . > "$sPipelinePath" 1>/dev/null 2>&1 & 
	
	sTimestamp=$(date +%s)
	#write to lastMusicCmd.xml
	xmlstarlet ed --inplace -u '//command' -v 'START' "$sMusicCmdInfo"
	xmlstarlet ed --inplace -u '//timestamp' -v "$sTimestamp" "$sMusicCmdInfo"
	xmlstarlet ed --inplace -u '//sender' -v 'PlaybackControl' "$sMusicCmdInfo"
}

function saveAllFileNames
{
	echo "" > $sPlaylistInfoFilePath #clear file
	for file in $FILES
    do
		echo "$file" >> $sPlaylistInfoFilePath #append to file
    done
}

function getRandomMusicTrack
{
	iMusicId=$(( $RANDOM % $iMusicFilesCount ))
	echo "${asMusicFilesList[$iMusicId]}"
}

function readConfig 
{
	sTrackInfoFilePath=$(xmlstarlet sel -t -m '//trackInfoFile' -v . <$sConfigFilePath)
	sPlaylistInfoFilePath=$(xmlstarlet sel -t -m '//playlistInfoFile' -v . <$sConfigFilePath)
	iShuffle=$(xmlstarlet sel -t -m '//shuffle' -v . <$sConfigFilePath)
	iRepeat=$(xmlstarlet sel -t -m '//repeat' -v . <$sConfigFilePath)
}

function playlistMode
{
	echo "entered playlist mode"
	echo "$sForcedFirstTrack"
	bSkipToTrack=true
	if [ -z "$sForcedFirstTrack" ]; then  
		bSkipToTrack=false
	fi
    for file in $FILES
    do
		if [ $bSkipToTrack == true ]; then
			if [ "$file" == "$sForcedFirstTrack" ]; then
				bSkipToTrack=false
				if [ $bShuffleWasActive == true ]; then #case if the track was played in the shuffle mode, don't need to play it twice
					continue
				fi
			else
				continue
			fi
		fi
		saveFileName "$file"
		bNewTrack=true
		while [[ $iRepeat == 1 || $bNewTrack == true ]]; do
			sendStarCmd
			saveVolumeSetting
			$PLAYER "$file" -s >>"$sStdOutFilePath" 2>>"$sStdErrFilePath" <"$sPipelinePath"
			readConfig
			if [ $iShuffle == 1 ]; then
				return 1
			fi
			bNewTrack=false
		done
    done
	return 0
}

function shuffleMode
{
	bShuffleWasActive=true
	echo "entered shuffle mode"
	readConfig
	while [ $iShuffle == 1 ]; do
		file="$(getRandomMusicTrack)" #getRandom file from folder
		saveFileName "$file"
		bNewTrack=true
		while [ $iShuffle == 1 ] && [[ $iRepeat == 1 || $bNewTrack == true ]]; do
			sendStarCmd
			saveVolumeSetting
			$PLAYER "$file" -s >>"$sStdOutFilePath" 2>>"$sStdErrFilePath" <"$sPipelinePath" 
			readConfig
			bNewTrack=false
		done
	done
	return 1
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
PLAYER="nohup omxplayer -o local"
sConfigFilePath=$1
sTrackInfoFilePath=$(xmlstarlet sel -t -m '//trackInfoFile' -v . <$sConfigFilePath)
sPlaylistInfoFilePath=$(xmlstarlet sel -t -m '//playlistInfoFile' -v . <$sConfigFilePath)
sMusicCmdInfo=$(xmlstarlet sel -t -m '//musicCmdInfo' -v . <$sConfigFilePath)
sPipelinePath=$(xmlstarlet sel -t -m '//ctrlPipelineDir' -v . <$sConfigFilePath)

bIsPlaylist=false
sMusicPath=$(xmlstarlet sel -t -m '//musicLocation' -v . <$sConfigFilePath)
if [[ -d $sMusicPath ]]; then
	bIsPlaylist=true
elif [[ -f $sMusicPath ]]; then
    bIsPlaylist=false
else
    echo "musicPath is not valid!"
    exit 1
fi
FILES="$sMusicPath/*"
bShuffleWasActive=false

sForcedFirstTrack=$(xmlstarlet sel -t -m '//firstTrack' -v . <$sConfigFilePath)

iShuffle=$(xmlstarlet sel -t -m '//shuffle' -v . <$sConfigFilePath)
iRepeat=$(xmlstarlet sel -t -m '//repeat' -v . <$sConfigFilePath)

sStdOutFilePath=$(xmlstarlet sel -t -m '//stdOutFile' -v . <$sConfigFilePath)
sStdErrFilePath=$(xmlstarlet sel -t -m '//stdErrFile' -v . <$sConfigFilePath)
# -------------------------------------------------------------------------------------------------

# ------------------------------- Check FilePaths -------------------------------------------------
isFileExistant $sTrackInfoFilePath
isFileExistant $sPlaylistInfoFilePath
# -------------------------------------------------------------------------------------------------

# --------------------------- Loaded Configuration Summary ----------------------------------------
echo "Configuration:"
echo "sMusicPath            - " $sMusicPath
echo "sConfigFilePath       - " $sConfigFilePath
echo "sTrackInfoFilePath    - " $sTrackInfoFilePath
echo "sPlaylistInfoFilePath - " $sPlaylistInfoFilePath
echo "bIsPlaylist           - " $bIsPlaylist
echo "sForcedFirstTrack     - " $sForcedFirstTrack
echo "sPipelinePath         - " $sPipelinePath
echo "iShuffle              - " $iShuffle
echo "iRepeat               - " $iRepeat
# -------------------------------------------------------------------------------------------------

# --------------------------- Create MusicFile Array ----------------------------------------------
asMusicFilesList=()
i=0
for file in $FILES
do
    asMusicFilesList[$i]="$file"
	i=$((i+1))
done
iMusicFilesCount=$i

declare -p asMusicFilesList
echo "${asMusicFilesList[0]}"
echo "${asMusicFilesList[5]}"
echo "${asMusicFilesList[10]}"
# -------------------------------------------------------------------------------------------------

# -------------------------------------------------------------------------------------------------
# ---------------------------- Main Execution Loops -----------------------------------------------
# -------------------------------------------------------------------------------------------------
if [ $bIsPlaylist == true ]; then
    saveAllFileNames
    echo "Starting playlist playback..."
	eRet=1
	while [ $eRet == 1 ]; do
	if [ $iShuffle == 1 ]; then
		shuffleMode
		eRet=$?
	elif [ $eRet == 1 ]; then
		playlistMode
		eRet=$?
	fi
	done
else
    echo "Starting single file playback..."
    for file in $sMusicPath
    do
		sendStarCmd
		saveVolumeSetting
		$PLAYER "$file" -s >>"$sStdOutFilePath" 2>>"$sStdErrFilePath" <"$sPipelinePath"
    done
fi
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------
# -------------------------------------------------------------------------------------------------