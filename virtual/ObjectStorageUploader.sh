#!/bin/bash
# ================================================================================
#     ObjectStorageUploader.sh
#     © Copyright IBM Corporation 2014.
#     LICENSE: MIT (http://opensource.org/licenses/MIT)    
# ================================================================================

#./objectstorageupload.sh dsl-4.4.10.iso 'myContainer/file.vhd' 'SLOS1234-1:SL1234' 'apikey'

fileToUpload=$1
swiftTargetPath=$2
swiftUsername=$3
swiftPassword=$4

swiftEndpoint='https://dal05.objectstorage.softlayer.net/auth/v1.0/'

apiResponse=$(curl -X GET -H "X-Storage-User: $swiftUsername" -H "X-Storage-Pass: $swiftPassword" -s -i $swiftEndpoint)
swiftAuthToken=$(echo "$apiResponse" | grep "X-Auth-Token:" | sed 's/X-Auth-Token: //g' | tr -d '\r')
swiftStorageUrl=$(echo "$apiResponse" | grep "X-Storage-Url:" | sed 's/X-Storage-Url: //g' | tr -d '\r')

fileSize=$(wc -c $fileToUpload | awk '{print $1}')
blockSize=1048576
let chunkSize=2048 #2GB chunks
let chunks=($fileSize/$blockSize+$chunkSize-1)/$chunkSize;

for ((i=0; i<chunks; i++))
do
   printf -v chunkName "chunk-%05d" $i
   let skipChunk=$i*chunkSize

   dd if=$fileToUpload bs=$blockSize count=$chunkSize skip=$skipChunk | curl -X PUT -H "X-Auth-Token: $swiftAuthToken" --data-binary @- "$swiftStorageUrl/$swiftTargetPath/$chunkName"
done

curl -X PUT -H "X-Auth-Token: $swiftAuthToken" -H "X-Object-Manifest: $swiftTargetPath" -H "Content-Length: 0" $swiftStorageUrl/$swiftTargetPath


