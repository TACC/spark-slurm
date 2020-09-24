# Configuration file for ipython-notebook.
import ssl

c = get_config()

c.IPKernelApp.pylab = 'inline'  # if you want plotting support always
c.NotebookApp.ip = '0.0.0.0'
c.NotebookApp.port = 5902
c.NotebookApp.open_browser = False
c.NotebookApp.mathjax_url = u'https://cdn.mathjax.org/mathjax/latest/MathJax.js'
c.NotebookApp.allow_origin = u'*'
c.NotebookApp.certfile = u'/home1/00832/envision/.viscert/vis.2015.04.pem'
c.NotebookApp.keyfile  = u'/home1/00832/envision/.viscert/vis.2015.04.pem'
c.NotebookApp.ssl_options={"ssl_version": ssl.PROTOCOL_TLSv1_2}
