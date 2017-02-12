
import smtplib
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
 
fromaddr = "elec292bestbiomedteam@gmail.com"
password = "praisejesus"
toaddr = "zachfu97@gmail.com"
msg = MIMEMultipart()
msg['From'] = fromaddr
msg['To'] = toaddr
msg['Subject'] = "TEST EMAIL"
 
body = "THIS FUCKING WORKS"
msg.attach(MIMEText(body, 'plain'))
 
server = smtplib.SMTP('smtp.gmail.com', 587)
server.starttls()
server.login(fromaddr, password)
text = msg.as_string()
server.sendmail(fromaddr, toaddr, text)
server.quit()