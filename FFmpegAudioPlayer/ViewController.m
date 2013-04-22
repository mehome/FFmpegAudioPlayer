//
//  ViewController.m
//  FFmpegAudioPlayer
//
//  Created by Liao KuoHsun on 13/4/19.
//  Copyright (c) 2013年 Liao KuoHsun. All rights reserved.
//

#import "ViewController.h"
#import "AudioPlayer.h"

#define WAV_FILE_NAME @"1.wav"

// If we read too fast, the size of aqQueue will increased quickly.
// If we read too slow, .
#define LOCAL_FILE_DELAY_MS 80  


// Reference for AAC test file
// http://download.wavetlan.com/SVV/Media/HTTP/http-aac.htm
// http://download.wavetlan.com/SVV/Media/RTSP/darwin-aac.htm


// === LOCAL File ===
//#define AUDIO_TEST_PATH @"AAC_12khz_Mono_5.aac"



// === Valid RTSP URL ===
//#define AUDIO_TEST_PATH @"rtsp://216.16.231.19/BlackBerry.3gp"
#define AUDIO_TEST_PATH @"rtsp://216.16.231.19/BlackBerry.mp4"
//#define AUDIO_TEST_PATH @"rtsp://mm2.pcslab.com/mm/7h800.mp4"
//#define AUDIO_TEST_PATH @"rtsp://216.16.231.19/The_Simpsons_S19E05_Treehouse_of_Horror_XVIII.3GP"


// === For Error Control Testing ===
// Test remote file
// Online Radio (can't play well)
//#define AUDIO_TEST_PATH @"rtsp://rtsplive.881903.com/radio-Web/cr2.3gp"

// Online Radio (invalid rtsp)
//#define AUDIO_TEST_PATH @"rtsp://211.89.225.101/live1"

// ("wma" audio format is no support)
// #define AUDIO_TEST_PATH @"rtsp://media.iwant-in.net/pop"





@interface ViewController (){
    UIAlertView *pLoadRtspAlertView;
    UIActivityIndicatorView *pIndicator;
}

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    return;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    NSLog(@"didReceiveMemoryWarning");
}

-(void)stopAlertView:(NSTimer *)timer {
    if(pLoadRtspAlertView!=nil)
    {        
        [pIndicator stopAnimating];
        [pLoadRtspAlertView dismissWithClickedButtonIndex:0 animated:YES];
        pIndicator = nil;
        pLoadRtspAlertView = nil;
        
        // Time out
        if(timer!=nil)
        {
            UIAlertView *pErrAlertView = [[UIAlertView alloc] initWithTitle:@"\n\nRTSP error"
                                                                message:nil delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
            [pErrAlertView show];
            [self.PlayAudioButton setTitle:@"Play" forState:UIControlStateNormal];             
        }
    }

}

-(void)startAlertView {
    pLoadRtspAlertView = [[UIAlertView alloc] initWithTitle:@"\n\nConnecting\nPlease Wait..."
                                                    message:nil delegate:self cancelButtonTitle:nil otherButtonTitles: nil];
    [pLoadRtspAlertView show];
    pIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    
    // Adjust the indicator so it is up a few pixels from the bottom of the alert
    pIndicator.center = CGPointMake(pLoadRtspAlertView.bounds.size.width / 2, pLoadRtspAlertView.bounds.size.height - 50);
    [pIndicator startAnimating];
    [pLoadRtspAlertView addSubview:pIndicator];
    
    // start a timer for 60 seconds, if rtsp cannot connect correctly.
    // we should dismiss alert view and let user can try again or leave this program
    [NSTimer scheduledTimerWithTimeInterval:30
                                     target:self
                                   selector:@selector(stopAlertView:)
                                   userInfo:nil
                                    repeats:NO];
}

- (IBAction)StopPlayAudio:(id)sender {
    
    // Stop Producer
    [self stopFFmpegAudioStream];
    
    // Stop Consumer
    [aPlayer Stop:FALSE];
    //aPlayer = nil;    
    
    // Release all resources generated by Producer
    [apQueue destroyQueue];
    //apQueue = nil;
    
    [self destroyFFmpegAudioStream];
}

- (IBAction)PlayAudio:(id)sender {
    UIButton *vBn = (UIButton *)sender;
    
    if([vBn.currentTitle isEqualToString:@"Stop"])
    {
        [vBn setTitle:@"Play" forState:UIControlStateNormal];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
            [self StopPlayAudio:nil];
        });
    }
    else
    {
        [vBn setTitle:@"Stop" forState:UIControlStateNormal];        
        [self startAlertView];        
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(void) {
            if([self initFFmpegAudioStream]==FALSE)
            {
                NSLog(@"initFFmpegAudio fail");
                dispatch_async(dispatch_get_main_queue(), ^(void) {
                [vBn setTitle:@"Play" forState:UIControlStateNormal];
                [self stopAlertView:nil];
                
                UIAlertView *pErrAlertView = [[UIAlertView alloc] initWithTitle:@"\n\nRTSP error"
                                                                message:nil delegate:self cancelButtonTitle:@"OK" otherButtonTitles: nil];
                [pErrAlertView show];
                });
                return;
            }
            
            apQueue = [[AudioPacketQueue alloc]initQueue];
            aPlayer = [[AudioPlayer alloc]initAudio:apQueue withCodecCtx:(AVCodecContext *) pAudioCodecCtx];
            
            // Dismiss alertview in main thread
            // Run Audio Player in main thread
            dispatch_async(dispatch_get_main_queue(), ^(void) {
                [self stopAlertView:nil];
                sleep(1);
                if([aPlayer getStatus]!=eAudioRunning)
                {
                    [aPlayer Play];
                }
                
            });
            
            // Read ffmpeg audio packet in another thread
            [self readFFmpegAudioFrameAndDecode];
                        
            [vBn setTitle:@"Play" forState:UIControlStateNormal];
            // wait, so that packet queue will buffer audio data for playing            
        });
    }
}

//-(void) initiOSAudio:(id) sender {
//    
//    // wait, so that packet queue will buffer audio data for playing
//    sleep(2);
//    
//    if([aPlayer getStatus]!=eAudioRunning)
//    {
//        [aPlayer Play];
//    }
//}

-(BOOL) initFFmpegAudioStream{
    
    NSString *pAudioInPath;
    AVCodec  *pAudioCodec;
    
    if( strncmp([AUDIO_TEST_PATH UTF8String], "rtsp", 4)==0)
    {
        pAudioInPath = AUDIO_TEST_PATH;
        IsLocalFile = FALSE;
    }
    else
    {
        pAudioInPath = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:AUDIO_TEST_PATH];
        IsLocalFile = TRUE;
    }
        
    avcodec_register_all();
    av_register_all();
    if(IsLocalFile!=TRUE)
    {
        avformat_network_init();
    }
    
    @synchronized(self)
    {
        pFormatCtx = avformat_alloc_context();
    }
    
#if 1 // TCP
    AVDictionary *opts = 0;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    NSLog(@"%@", pAudioInPath);
    
    // Open video file
    if(avformat_open_input(&pFormatCtx, [pAudioInPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, &opts) != 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
        return FALSE;
    }
	av_dict_free(&opts);
#else // UDP
    if(avformat_open_input(&pFormatCtx, [pAudioInPath cStringUsingEncoding:NSASCIIStringEncoding], NULL, NULL) != 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't open file\n");
        return FALSE;
    }
#endif
    
    pAudioInPath = nil;
    
    // Retrieve stream information
    if(avformat_find_stream_info(pFormatCtx,NULL) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Couldn't find stream information\n");
        return FALSE;
    }
    
    // Dumpt stream information
    av_dump_format(pFormatCtx, 0, [pAudioInPath UTF8String], 0);
    
    
    // 20130329 albert.liao modified start
    // Find the first video stream
    if ((audioStream =  av_find_best_stream(pFormatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &pAudioCodec, 0)) < 0) {
        av_log(NULL, AV_LOG_ERROR, "Cannot find a audio stream in the input file\n");
        return FALSE;
    }
	
    if(audioStream>=0){
        
        NSLog(@"== Audio pCodec Information");
        NSLog(@"name = %s",pAudioCodec->name);
        NSLog(@"sample_fmts = %d",*(pAudioCodec->sample_fmts));
        if(pAudioCodec->profiles)
            NSLog(@"profiles = %s",pAudioCodec->name);
        else
            NSLog(@"profiles = NULL");
        
        // Get a pointer to the codec context for the video stream
        pAudioCodecCtx = pFormatCtx->streams[audioStream]->codec;
        
        // Find the decoder for the video stream
        pAudioCodec = avcodec_find_decoder(pAudioCodecCtx->codec_id);
        if(pAudioCodec == NULL) {
            av_log(NULL, AV_LOG_ERROR, "Unsupported audio codec!\n");
            return FALSE;
        }
        
        // Open codec
        if(avcodec_open2(pAudioCodecCtx, pAudioCodec, NULL) < 0) {
            av_log(NULL, AV_LOG_ERROR, "Cannot open audio decoder\n");
            return FALSE;
        }
    }
    
    IsStop = FALSE;
    
    return TRUE;
}

-(void) stopFFmpegAudioStream{
    IsStop = TRUE;
    NSLog(@"stopFFmpegAudioStream");
}

-(void) destroyFFmpegAudioStream{
    IsStop = TRUE;
    NSLog(@"destroyFFmpegAudioStream");

    avformat_network_deinit();
    
// When IsStop == TRUE,
// the pFormatCtx and pAudioCodecCtx will be released in readFFmpegFrame automatically
//    @synchronized(self)
//    {
//        if (pAudioCodecCtx) {
//            avcodec_close(pAudioCodecCtx);
//            pAudioCodecCtx = NULL;
//        }
//        if (pFormatCtx) {
//            avformat_close_input(&pFormatCtx);
//            //av_close_input_file(pFormatCtx);
//        }
//    }
    
}


-(void) readFFmpegAudioFrameAndDecode {
    int vErr;
    AVPacket vxPacket;
    av_init_packet(&vxPacket);    
    
    if(IsLocalFile == TRUE)
    {
        while(IsStop==FALSE)
        {
            vErr = av_read_frame(pFormatCtx, &vxPacket);
            if(vErr>=0)
            {
                if(vxPacket.stream_index==audioStream) {
                    int ret = [apQueue putAVPacket:&vxPacket];
                    if(ret <= 0)
                        NSLog(@"Put Audio Packet Error!!");
                    
                    // TODO: use pts/dts to decide the delay time 
                    usleep(1000*LOCAL_FILE_DELAY_MS);
                    
//                    if(packet.pts != AV_NOPTS_VALUE)
//                    {
//                        audioClock = av_q2d(pAudioCodecCtx->time_base)*packet.dts;
//                    }
                }
                else
                {
                    //NSLog(@"receive unexpected packet!!");
                    av_free_packet(&vxPacket);
                }
            }
            else
            {
                NSLog(@"av_read_frame error :%s", av_err2str(vErr));
                IsStop = TRUE;
            }
        }
    }
    else
    {
        while(IsStop==FALSE)
        {
            vErr = av_read_frame(pFormatCtx, &vxPacket);
            
            if(vErr==AVERROR_EOF)
            {
                NSLog(@"av_read_frame error :%s", av_err2str(vErr));
                IsStop = TRUE;
            }
            else if(vErr==0)
            {
                if(vxPacket.stream_index==audioStream) {
                    int ret = [apQueue putAVPacket:&vxPacket];
                    if(ret <= 0)
                        NSLog(@"Put Audio Packet Error!!");
                }
                else
                {
                    //NSLog(@"receive unexpected packet!!");
                    av_free_packet(&vxPacket);
                }
            }
            else
            {
                NSLog(@"av_read_frame error :%s", av_err2str(vErr));
                IsStop = TRUE;
            }
        }
    }
    
    if (pAudioCodecCtx) {
        avcodec_close(pAudioCodecCtx);
        pAudioCodecCtx = NULL;
    }
    if (pFormatCtx) {
        avformat_close_input(&pFormatCtx);
    }
    NSLog(@"Leave ReadFrame and close pFormatCtx");
}

@end