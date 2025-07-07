This is meant to install local CUDA for Zonos if you PC has a second card installed.

1. BEFORE installation run GPUINFO.bat to see the CUDA numbers of you GPUS.....if the GPU you want is number 1, then there is no need to change anything, skip to step 4.

2  Using notepad or notepad ++ (HIGHLY RECCOMEND NOTEPAD ++) Open the files EXACTLY NAMED, 
                 a. download_models.py, - located in line 7 of code as "  os.environ['CUDA_VISIBLE_DEVICES'] = '1'  " 
                 b. zonos_download_models, located in line 6 of code as "export CUDA_VISIBLE_DEVICES=1
                 c. start_zonos located in line 6 of code as "export CUDA_VISIBLE_DEVICES=1"

3. Change "CUDA_VISIBLE_DEVICES=1" lines in those files to the card number you want to use.
 
4. Run InstallZonos.bat

5. Run StartZonos.bat 

If something messes up, I've added a bat file that uninstalls Zonos from WSL (CHIM)
Just run UninstallZonos.bat and repeat above steps. 



THIS IS FOR A SECOND CARD IN YOUR PC, NOT REALLY A CONNECTION TO USE A CARD ON A SECOND PC OVER SERVER (unless that PC has multiple cards). You don't need CHIM installed on second PC, just this Zonos file. That's a little different then what this though. Basically following the guide:https://dwemerdynamics.hostwiki.io/en/2nd-PC-Guide, BUT USE YOUR WIFI LAN IP!  
*********Thanks to Syd for discovering this!********   



********EXPERIMENTAL*********
There is an additional folder called Gradio_InterfacePY_Types. This is experimental and used AFTER the ZONOS install. These are 3 modifications of the gradio_interface.py file
located at \\wsl.localhost\DwemerAI4Skyrim3\home\dwemer\Zonos. You are more than welcomed to try the modified files out. I personally have not seen hardly any difference in the attempted optimizations. But have heard the Prevent Gradient variant of the file is doing well on 3080 for whatever reason. If you want to try each and see how they impact inference times in Zonos feel free. There is an Original copy in there so you don't lose it. I myself hardly see any difference. Here are my time comparisons using the same statement:


Tested on a 4070ti: 
Original:
25.547291040421 secs in zonos_gradio cal 
25.723440885544 secs in zonos_gradio call 
25.846412181854 secs in zonos_gradio call  


Inference Mode:
28.270838022232 secs in zonos_gradio call 
25.766465187073 secs in zonos_gradio call
25.826145887375 secs in zonos_gradio call

My torch.no_grad() changes : (in game benefits may come from limited 10sec outputs)    
24.6480448246 secs in zonos_gradio call 
25.891779899597 secs in zonos_gradio call 
25.797730207443 secs in zonos_gradio call 


BFloat16Mod:
25.62069606781 secs in zonos_gradio call
25.686585903168 secs in zonos_gradio call
25.739050865173 secs in zonos_gradio call


If you notice any one of these clearly performing better than another IN GAME (or not) I'd like to hear about it, reach out to me on the CHIM or SHOR-LM Discord @Wondernutts. You can also reach out to me directly if you have issues running on your second card, I can't help you if you are trying to connect to another PC. I don't have that setup.  
 
 
