FROM colmap/colmap
LABEL maintainer="fullstability@gmail.com"
RUN apt update && apt install -y ffmpeg
RUN apt-get update && apt-get install -y bash
ENV QT_QPA_PLATFORM=offscreen


COPY ./src /src
WORKDIR /src
RUN chmod +x ./action
ENTRYPOINT ["./action"]