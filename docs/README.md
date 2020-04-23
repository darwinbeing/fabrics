# Build the docs

## For PDF
```
pip install -r requirements.txt
make latexpdf
evince build/latex/interconnect_ip.pdf
```

## HTML
```
pip install -r requirements.txt
make html
firefox build/html/index.html
```
