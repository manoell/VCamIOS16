#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

// -------------------- SISTEMA DE LOG --------------------
static NSString *getVCamLogPath() {
    return @"/tmp/vcam_debug.log";
}

static void vcam_log(NSString *message) {
    static dispatch_queue_t logQueue = nil;
    static NSDateFormatter *dateFormatter = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        logQueue = dispatch_queue_create("com.vcam.log", DISPATCH_QUEUE_SERIAL);
        dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    });
    
    dispatch_async(logQueue, ^{
        NSString *timestamp = [dateFormatter stringFromDate:[NSDate date]];
        NSString *logMessage = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
        NSString *logPath = getVCamLogPath();
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
            [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
        if (fileHandle) {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
        }
    });
}

static void vcam_logf(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    vcam_log(message);
}
// -------------------- FIM DO SISTEMA DE LOG --------------------

// Variáveis globais
static NSFileManager *g_fileManager = nil;
static BOOL g_cameraRunning = NO;
static CALayer *g_maskLayer = nil;
static AVPlayer *g_player = nil;
static AVPlayerLayer *g_playerLayer = nil;
static NSString *g_videoFile = @"/tmp/default.mp4";

// Hook na layer de preview da câmera
%hook AVCaptureVideoPreviewLayer

// Método que é chamado quando uma sublayer é adicionada
-(void)addSublayer:(CALayer *)layer {
    // Chamamos o método original primeiro
    %orig;
    
    vcam_logf(@"Adicionando sublayer: %@", layer);
    
    // Configurar DisplayLink para atualizações contínuas se não existir
    static CADisplayLink *displayLink = nil;
    if (displayLink == nil) {
        displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(step:)];
        displayLink.preferredFramesPerSecond = 30;
        [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        vcam_log(@"DisplayLink configurado");
    }
    
    // Verificar se nossas camadas já foram adicionadas a esta layer
    if (![[self sublayers] containsObject:g_maskLayer] && ![[self sublayers] containsObject:g_playerLayer]) {
        vcam_log(@"Configurando camadas...");
        
        // 1. Criar camada preta (máscara)
        g_maskLayer = [CALayer layer];
        g_maskLayer.backgroundColor = [UIColor blackColor].CGColor;
        g_maskLayer.frame = self.bounds;
        g_maskLayer.opacity = 1.0;
        
        // 2. Inserir a camada preta acima de todas as outras
        [self addSublayer:g_maskLayer];
        vcam_log(@"Camada preta adicionada");
        
        // 3. Verificar se o arquivo de vídeo existe
        if ([g_fileManager fileExistsAtPath:g_videoFile]) {
            // 4. Criar e configurar o player de vídeo
            NSURL *videoURL = [NSURL fileURLWithPath:g_videoFile];
            g_player = [AVPlayer playerWithURL:videoURL];
            g_player.actionAtItemEnd = AVPlayerActionAtItemEndNone; // Para loop contínuo
            g_player.volume = 0.0; // Sem áudio
            
            // 5. Criar a camada do player
            g_playerLayer = [AVPlayerLayer playerLayerWithPlayer:g_player];
            g_playerLayer.frame = self.bounds;
            g_playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
            
            // 6. Inserir a camada do vídeo acima da camada preta
            [self addSublayer:g_playerLayer];
            
            // 7. Iniciar reprodução
            [g_player play];
            
            // 8. Configurar notificação para reiniciar vídeo quando terminar
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(playerItemDidReachEnd:)
                                                         name:AVPlayerItemDidPlayToEndTimeNotification
                                                       object:g_player.currentItem];
            
            vcam_log(@"Camada de vídeo configurada e reprodução iniciada");
        } else {
            vcam_logf(@"Arquivo de vídeo não encontrado: %@", g_videoFile);
        }
    }
}

// Método para lidar com o fim do vídeo
%new
-(void)playerItemDidReachEnd:(NSNotification *)notification {
    vcam_log(@"Vídeo terminou, reiniciando");
    [g_player seekToTime:kCMTimeZero];
    [g_player play];
}

// Método para atualização contínua
%new
-(void)step:(CADisplayLink *)sender {
    // Verificar se o arquivo de vídeo existe
    BOOL fileExists = [g_fileManager fileExistsAtPath:g_videoFile];
    
    // Atualizar as dimensões das camadas para corresponder ao tamanho atual
    if (g_maskLayer) {
        g_maskLayer.frame = self.bounds;
    }
    
    if (g_playerLayer) {
        g_playerLayer.frame = self.bounds;
        
        // Se o player parou por algum motivo, reiniciar
        if (g_player && g_player.rate == 0) {
            [g_player play];
            vcam_log(@"Reprodução reiniciada");
        }
    }
    
    // Log periódico de status
    static NSTimeInterval lastLogTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    if (currentTime - lastLogTime > 5.0) {
        vcam_logf(@"Status: arquivo=%d, cameraAtiva=%d", fileExists, g_cameraRunning);
        lastLogTime = currentTime;
    }
}

%end

// Hook em AVCaptureSession para rastrear quando a câmera está ativa
%hook AVCaptureSession

-(void)startRunning {
    vcam_log(@"Câmera iniciando");
    g_cameraRunning = YES;
    %orig;
}

-(void)stopRunning {
    vcam_log(@"Câmera parando");
    g_cameraRunning = NO;
    %orig;
}

%end

// Inicialização do tweak
%ctor {
    vcam_log(@"--------------------------------------------------");
    vcam_log(@"VCamTeste - Inicializando tweak");
    
    g_fileManager = [NSFileManager defaultManager];
    
    if ([[NSProcessInfo processInfo] isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){16, 0, 0}]) {
        vcam_log(@"iOS 16 detectado");
    }
    
    vcam_logf(@"Caminho do vídeo: %@", g_videoFile);
    vcam_logf(@"Processo atual: %@", [NSProcessInfo processInfo].processName);
    vcam_log(@"Tweak inicializado com sucesso");
}

// Finalização
%dtor {
    vcam_log(@"VCamTeste - Finalizando tweak");
    g_fileManager = nil;
    g_maskLayer = nil;
    g_playerLayer = nil;
    g_player = nil;
    vcam_log(@"Tweak finalizado");
    vcam_log(@"--------------------------------------------------");
}
