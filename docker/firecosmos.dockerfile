FROM alpine AS release

RUN apk add wget
RUN apk add bash
RUN wget https://github.com/graphprotocol/firehose-cosmos/releases/download/v0.6.0/firecosmos_linux_amd64 -O firecosmos

# make executable
RUN chmod +x firecosmos

# move firecosmos to bin
RUN mv firecosmos /usr/local/bin

# set as cmd
# CMD ["firecosmos"]