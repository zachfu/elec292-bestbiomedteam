import numpy as np
import matplotlib
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import sys, time, math
import time
import serial

ser = serial.Serial(
    port='COM4',
    baudrate=115200,
    parity=serial.PARITY_NONE,
    stopbits=serial.STOPBITS_TWO,
    bytesize=serial.EIGHTBITS
)

xsize=500
   
def data_gen():
    t = 0
    while True:
       t+=1
       tempin = float(ser.readline())
       temp=tempin/100.0
       yield t, temp

def get_colour(t):
    cmap = matplotlib.cm.get_cmap('gist_rainbow')
    return cmap(t*2%300)

def on_close_figure(event):
    sys.exit(0)

data_gen.t = -1
fig = plt.figure()
fig.canvas.mpl_connect('close_event', on_close_figure)
ax = fig.add_subplot(111)
ax.set_axis_bgcolor('k')
ax.set_ylim(-50, 150)
ax.set_xlim(0, xsize)
ax.grid()
line, = ax.plot([], [], '-',marker='D',mec='w',mew=1,markevery=3,lw=5,label='\nTemperature line\n')
legend = ax.legend(loc='upper left', shadow=True)
gridlines = ax.get_xgridlines() + ax.get_ygridlines()
ticklabels = ax.get_xticklabels() + ax.get_yticklabels()
frame = legend.get_frame()
frame.set_facecolor('0.9')
plt.ylabel('Temperature(°C)')
plt.xlabel('Time(s)')
plt.title('Real-time Temperature monitoring')
xdata, ydata = [], []

for label in legend.get_texts():
    label.set_fontsize('large')

for label in legend.get_lines():
    label.set_linewidth(1.5)

for lline in gridlines:
    lline.set_linestyle('-.')
    lline.set_color('gray')
    lline.set_linewidth(1)
    
for label in ticklabels:
    label.set_color('darkgreen')
    label.set_fontsize('large')
    
def run(data):
    # update the data
    t,y = data
    if t>-1:
        xdata.append(t)
        ydata.append(y)
        if t>xsize: # Scroll to the left.
            ax.set_xlim(t-xsize, t)
        line.set_data(xdata, ydata)
        line.set_color(get_colour(t))
    return line,

ani = animation.FuncAnimation(fig, run, data_gen, blit=False, interval=100, repeat=False)
plt.show()

