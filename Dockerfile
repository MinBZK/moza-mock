FROM wiremock/wiremock:3.13.2

COPY mappings/ /home/wiremock/mappings/
COPY __files/ /home/wiremock/__files/
