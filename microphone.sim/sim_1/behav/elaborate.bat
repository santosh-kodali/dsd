@echo off
set xv_path=C:\\Xilinx\\Vivado\\2016.4\\bin
call %xv_path%/xelab  -wto a336b728aceb4fbd9537ecbea2de6e51 -m64 --debug typical --relax --mt 2 -L xil_defaultlib -L secureip --snapshot audio_behav xil_defaultlib.audio -log elaborate.log
if "%errorlevel%"=="0" goto SUCCESS
if "%errorlevel%"=="1" goto END
:END
exit 1
:SUCCESS
exit 0
