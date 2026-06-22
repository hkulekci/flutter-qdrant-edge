//! On-device dense text embeddings using a pure-Rust BERT runtime (candle).
//!
//! Loads a sentence-transformers MiniLM model (config.json + tokenizer.json +
//! model.safetensors) from a directory and produces L2-normalized 384-d
//! sentence vectors via mean pooling — the same recipe as the official candle
//! BERT example. Pure Rust means it cross-compiles to iOS/Android like the rest
//! of the crate, with no ONNX Runtime native dependency.

use candle_core::{DType, Device, Tensor};
use candle_nn::VarBuilder;
use candle_transformers::models::bert::{BertModel, Config};
use tokenizers::Tokenizer;

/// Output dimensionality of all-MiniLM-L6-v2.
pub const DENSE_DIM: usize = 384;

pub struct TextEmbedder {
    model: BertModel,
    tokenizer: Tokenizer,
    device: Device,
}

impl TextEmbedder {
    /// Load the model from a directory containing config.json, tokenizer.json
    /// and model.safetensors.
    pub fn load(model_dir: &str) -> Result<Self, String> {
        let device = Device::Cpu;

        let config_str = std::fs::read_to_string(format!("{model_dir}/config.json"))
            .map_err(|e| format!("read config.json: {e}"))?;
        let config: Config =
            serde_json::from_str(&config_str).map_err(|e| format!("parse config: {e}"))?;

        let tokenizer = Tokenizer::from_file(format!("{model_dir}/tokenizer.json"))
            .map_err(|e| format!("load tokenizer: {e}"))?;

        let weights = format!("{model_dir}/model.safetensors");
        let vb = unsafe {
            VarBuilder::from_mmaped_safetensors(&[weights], DType::F32, &device)
                .map_err(|e| format!("load weights: {e}"))?
        };
        let model = BertModel::load(vb, &config).map_err(|e| format!("build model: {e}"))?;

        Ok(Self { model, tokenizer, device })
    }

    /// Embed one text into an L2-normalized 384-d vector.
    pub fn embed(&self, text: &str) -> Result<Vec<f32>, String> {
        let encoding = self
            .tokenizer
            .encode(text, true)
            .map_err(|e| format!("tokenize: {e}"))?;
        let ids = encoding.get_ids();
        if ids.is_empty() {
            return Ok(vec![0.0; DENSE_DIM]);
        }

        let token_ids = Tensor::new(ids, &self.device)
            .and_then(|t| t.unsqueeze(0))
            .map_err(|e| e.to_string())?;
        let token_type_ids = token_ids.zeros_like().map_err(|e| e.to_string())?;

        // [1, n_tokens, hidden]
        let hidden = self
            .model
            .forward(&token_ids, &token_type_ids, None)
            .map_err(|e| format!("forward: {e}"))?;

        // Mean pool over tokens, then L2-normalize.
        let (_b, n_tokens, _h) = hidden.dims3().map_err(|e| e.to_string())?;
        let mean = (hidden.sum(1).map_err(|e| e.to_string())? / n_tokens as f64)
            .map_err(|e| e.to_string())?;
        let norm = mean
            .sqr()
            .and_then(|t| t.sum_keepdim(1))
            .and_then(|t| t.sqrt())
            .map_err(|e| e.to_string())?;
        let normalized = mean.broadcast_div(&norm).map_err(|e| e.to_string())?;

        normalized
            .squeeze(0)
            .and_then(|t| t.to_vec1::<f32>())
            .map_err(|e| e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Points at the local dev model (gitignored, downloaded for tests).
    fn model_dir() -> Option<String> {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/.models/minilm").to_string();
        if std::path::Path::new(&format!("{dir}/model.safetensors")).exists() {
            Some(dir)
        } else {
            None
        }
    }

    fn cosine(a: &[f32], b: &[f32]) -> f32 {
        a.iter().zip(b).map(|(x, y)| x * y).sum()
    }

    #[test]
    fn embeds_and_captures_meaning() {
        let Some(dir) = model_dir() else {
            eprintln!("SKIP: model not found; run download first");
            return;
        };
        let emb = TextEmbedder::load(&dir).expect("load model");

        let a = emb.embed("a cat is sleeping on the sofa").unwrap();
        let b = emb.embed("a feline naps on the couch").unwrap();
        let c = emb.embed("quarterly tax revenue rose sharply").unwrap();

        assert_eq!(a.len(), DENSE_DIM);

        let sim_related = cosine(&a, &b); // paraphrase, almost no shared words
        let sim_unrelated = cosine(&a, &c);
        eprintln!("related={sim_related:.3} unrelated={sim_unrelated:.3}");
        assert!(
            sim_related > sim_unrelated + 0.1,
            "semantic similarity should rank the paraphrase higher (related={sim_related}, unrelated={sim_unrelated})"
        );
    }
}
