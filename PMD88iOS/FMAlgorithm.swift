class FMAlgorithm {
    // アルゴリズムタイプ
    private var algorithmType: FMAlgorithmType = .alg0
    
    // フィードバック量
    private var feedbackLevel: Int = 0
    
    // 前回のオペレータ出力（フィードバック用）
    private var previousOp1Output: Float = 0.0
    private var previousOp1Output2: Float = 0.0
    
    // 初期化
    init() {
        setAlgorithm(algorithm: 0, feedback: 0)
    }
    
    // レジスタ値からアルゴリズムとフィードバックを設定
    func setRegister(value: UInt8) {
        let algorithm = Int(value & 0x07)
        let feedback = Int((value >> 3) & 0x07)
        setAlgorithm(algorithm: algorithm, feedback: feedback)
    }
    
    // アルゴリズムとフィードバックの設定
    func setAlgorithm(algorithm: Int, feedback: Int) {
        // アルゴリズムタイプの設定（0-7）
        if let algType = FMAlgorithmType(rawValue: algorithm & 0x07) {
            algorithmType = algType
        } else {
            algorithmType = .alg0
        }
        
        // フィードバックレベルの設定（0-7）
        feedbackLevel = feedback & 0x07
    }
    
    // アルゴリズムタイプを取得
    func getAlgorithmType() -> FMAlgorithmType {
        return algorithmType
    }
    
    // フィードバックレベルを取得
    func getFeedback() -> Int {
        return feedbackLevel
    }
    
    // フィードバック量の計算
    public func calculateFeedback(op1Output: Float) -> Float {
        if feedbackLevel == 0 {
            return 0.0
        }
        
        // フィードバック量の計算（前回と前々回の出力の平均）
        let feedback = (previousOp1Output + previousOp1Output2) / 2.0
        
        // フィードバックレベルに応じたスケーリング（0.0〜1.0の範囲）
        let scaleFactor = Float(feedbackLevel) / 8.0
        
        // 現在の出力を保存（次回のフィードバック計算用）
        previousOp1Output2 = previousOp1Output
        previousOp1Output = op1Output
        
        return feedback * scaleFactor
    }
    
    // オペレータの出力を計算
    func calculateOutput(op1: Float, op2: Float, op3: Float, op4: Float) -> Float {
        // フィードバック量の計算
        let feedback = calculateFeedback(op1Output: op1)
        
        // アルゴリズムに応じた出力の計算
        switch algorithmType {
        case .alg0:
            // アルゴリズム0: OP1 -> OP2 -> OP3 -> OP4
            return processAlgorithm0(op1: op1, op2: op2, op3: op3, op4: op4, feedback: feedback)
            
        case .alg1:
            // アルゴリズム1: (OP1 + OP2) -> OP3 -> OP4
            return processAlgorithm1(op1: op1, op2: op2, op3: op3, op4: op4, feedback: feedback)
            
        case .alg2:
            // アルゴリズム2: OP1 -> (OP2 + OP3) -> OP4
            return processAlgorithm2(op1: op1, op2: op2, op3: op3, op4: op4, feedback: feedback)
            
        case .alg3:
            // アルゴリズム3: OP1 -> OP2, OP3 -> OP4
            return processAlgorithm3(op1: op1, op2: op2, op3: op3, op4: op4, feedback: feedback)
            
        case .alg4:
            // アルゴリズム4: OP1 -> OP2, OP3, OP4
            return processAlgorithm4(op1: op1, op2: op2, op3: op3, op4: op4, feedback: feedback)
            
        case .alg5:
            // アルゴリズム5: OP1, OP2 -> OP3, OP4
            return processAlgorithm5(op1: op1, op2: op2, op3: op3, op4: op4, feedback: feedback)
            
        case .alg6, .alg7:
            // アルゴリズム6、7: OP1, OP2, OP3, OP4
            return processAlgorithm6(op1: op1, op2: op2, op3: op3, op4: op4, feedback: feedback)
        }
    }
    
    // アルゴリズム0: OP1 -> OP2 -> OP3 -> OP4
    private func processAlgorithm0(op1: Float, op2: Float, op3: Float, op4: Float, feedback: Float) -> Float {
        let modulated1 = op1 * (1.0 + feedback)
        let modulated2 = op2 * modulated1
        let modulated3 = op3 * modulated2
        let output = op4 * modulated3
        
        return output
    }
    
    // アルゴリズム1: (OP1 + OP2) -> OP3 -> OP4
    private func processAlgorithm1(op1: Float, op2: Float, op3: Float, op4: Float, feedback: Float) -> Float {
        let modulated1 = op1 * (1.0 + feedback)
        let combined = modulated1 + op2
        let modulated3 = op3 * combined
        let output = op4 * modulated3
        
        return output
    }
    
    // アルゴリズム2: OP1 -> (OP2 + OP3) -> OP4
    private func processAlgorithm2(op1: Float, op2: Float, op3: Float, op4: Float, feedback: Float) -> Float {
        let modulated1 = op1 * (1.0 + feedback)
        let modulated2 = op2 * modulated1
        let modulated3 = op3 * modulated1
        let combined = modulated2 + modulated3
        let output = op4 * combined
        
        return output
    }
    
    // アルゴリズム3: OP1 -> OP2, OP3 -> OP4
    private func processAlgorithm3(op1: Float, op2: Float, op3: Float, op4: Float, feedback: Float) -> Float {
        let modulated1 = op1 * (1.0 + feedback)
        let modulated2 = op2 * modulated1
        let modulated4 = op4 * op3
        
        return modulated2 + modulated4
    }
    
    // アルゴリズム4: OP1 -> OP2, OP3, OP4
    private func processAlgorithm4(op1: Float, op2: Float, op3: Float, op4: Float, feedback: Float) -> Float {
        let modulated1 = op1 * (1.0 + feedback)
        let modulated2 = op2 * modulated1
        
        return modulated2 + op3 + op4
    }
    
    // アルゴリズム5: OP1, OP2 -> OP3, OP4
    private func processAlgorithm5(op1: Float, op2: Float, op3: Float, op4: Float, feedback: Float) -> Float {
        let modulated1 = op1 * (1.0 + feedback)
        let modulated3 = op3 * modulated1
        let modulated4 = op4 * op2
        
        return modulated3 + modulated4
    }
    
    // アルゴリズム6: OP1, OP2, OP3, OP4
    private func processAlgorithm6(op1: Float, op2: Float, op3: Float, op4: Float, feedback: Float) -> Float {
        let modulated1 = op1 * (1.0 + feedback)
        
        return modulated1 + op2 + op3 + op4
    }
    
    // オペレータがキャリア（出力に直接寄与する）かどうかを判定
    func isCarrier(operatorIndex: Int) -> Bool {
        switch algorithmType {
        case .alg0, .alg1, .alg2:
            // OP4のみがキャリア
            return operatorIndex == 3
            
        case .alg3:
            // OP2とOP4がキャリア
            return operatorIndex == 1 || operatorIndex == 3
            
        case .alg4:
            // OP2、OP3、OP4がキャリア
            return operatorIndex == 1 || operatorIndex == 2 || operatorIndex == 3
            
        case .alg5:
            // OP3とOP4がキャリア
            return operatorIndex == 2 || operatorIndex == 3
            
        case .alg6, .alg7:
            // すべてのオペレータがキャリア
            return true
        }
    }
}