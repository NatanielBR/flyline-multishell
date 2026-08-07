FROM demo-base-standalone AS demo-builder

COPY tapes/demo_flycomp_fish.tape .

RUN faketime @1771881894 /home/john/bin/evp demo_flycomp_fish.tape

FROM scratch
COPY --from=demo-builder /app/*.gif /app/*.svg /
